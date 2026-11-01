;; Concrete TCP and UDP operations. A handler can replace either effect in a
;; test. By default, an operation that waits starts on the native host and
;; waits for its completion as a task does, by ticket ((snail shell task)'s
;; `through-host`), so each such operation's latent row names `tasks`.
;;
;; An Endpoint is parsed once, by `endpoint`: the type is exported without
;; its constructor, so holding one is evidence that its address is IPv4
;; and its port in range, and no host checks either again.
(define-library (snail shell socket)
  (export
   tcp listen connect accept read write finish-connection close-listener close-connection
   udp bind send receive close-udp
   Endpoint endpoint Endpoint-address Endpoint-port
   Listener Listener-token Listener-port
   Connection Connection-token
   UdpSocket UdpSocket-token UdpSocket-port
   Datagram Datagram-peer Datagram-bytes
   SocketError SocketError-code)
  (import
   (snail core base)
   (prefix (snail runtime native socket) host-)
   (only (snail shell task) tasks through-host))
  (begin

    ;; ---- Endpoints ----

    ;; An IPv4 address, its four octets in one number from 0 to 2^32 - 1,
    ;; most significant first, and a port from 0 to 65535.
    (struct Ipv4Endpoint
      ((address I64)
       (port I32)))

    (type Endpoint Ipv4Endpoint)

    ;; The Endpoint for dotted IPv4 text and a port, or EINVAL, the code a
    ;; host gives an address it cannot use.
    (: endpoint (-> String I32 (Result Endpoint SocketError)))
    (define (endpoint address port)
      (match (ipv4-address address)
        ((Some octets)
         (if (and (>= port 0) (<= port 65535))
             (Ok (Ipv4Endpoint octets port))
             (Err (SocketError "EINVAL"))))
        ((None) (Err (SocketError "EINVAL")))))

    ;; Four decimal octets from 0 to 255 between dots, none with a leading
    ;; zero, as Node's isIPv4 reads an address.
    (: ipv4-address (-> String (Option I64)))
    (define (ipv4-address text)
      (let loop ((index 0) (dots 0) (digits 0) (octet 0) (address 0))
        (if (= index (string-length text))
            (if (and (= dots 3) (> digits 0)) (Some (+ (* address 256) octet)) (None))
            (let* ((char (string-ref text index)) (next (+ (* octet 10) (digit-value char))))
              (cond ((and (char=? char #\.) (> digits 0) (< dots 3))
                     (loop (+ index 1) (+ dots 1) 0 0 (+ (* address 256) octet)))
                    ((and (char-numeric? char) (not (and (= digits 1) (= octet 0))) (<= next 255))
                     (loop (+ index 1) dots (+ digits 1) next address))
                    (else (None)))))))

    ;; The address as dotted text.
    (: Endpoint-address (-> Endpoint String))
    (define (Endpoint-address endpoint)
      (let ((address (Ipv4Endpoint-address endpoint)))
        (string-join (map (lambda (place) (i64->string (remainder (quotient address place) 256)))
                          (list 16777216 65536 256 1))
                     ".")))

    (: Endpoint-port (-> Endpoint I32))
    (define (Endpoint-port endpoint)
      (Ipv4Endpoint-port endpoint))

    ;; ---- Bounds ----

    ;; What the operations accept, decided here so no host decides it: a
    ;; read of 1 to 65,536 bytes, a datagram of at most 65,507, the most
    ;; an IPv4 datagram carries, and a grace that is not negative. A
    ;; listener keeps at most `accept-backlog` connections no accept has
    ;; claimed, and a UDP socket `datagram-queue` datagrams no receive has
    ;; taken; the host refuses what arrives beyond them.
    (: read-limit I32)
    (define read-limit 65536)

    (: datagram-limit I32)
    (define datagram-limit 65507)

    (: accept-backlog I32)
    (define accept-backlog 64)

    (: datagram-queue I32)
    (define datagram-queue 32)

    ;; ---- Public values ----

    ;; Tokens belong to the effect handler that created them. Any keeps a
    ;; native endpoint opaque, and lets tests use their own tokens.
    ;; Closing a native endpoint revokes every alias; it does not consume one.
    (struct Listener
      ((token Any)
       (port I32)))

    (struct Connection
      ((token Any)))

    (struct UdpSocket
      ((token Any)
       (port I32)))

    (struct Datagram
      ((peer Endpoint)
       (bytes Bytes)))

    (struct SocketError
      ((code String)))

    (effect tcp
      ((listen (-> Endpoint (Result Listener SocketError) ! tasks))
       (connect (-> Endpoint (Result Connection SocketError) ! tasks))
       (accept (-> Listener (Result Connection SocketError) ! tasks))
       (read (-> Connection I32 (Result (Option Bytes) SocketError) ! tasks))
       (write (-> Connection Bytes (Result I32 SocketError) ! tasks))
       (finish-connection (-> Connection I32 (Result Unit SocketError) ! tasks))
       (close-listener (-> Listener (Result Unit SocketError)))
       (close-connection (-> Connection (Result Unit SocketError))))
      (default
        ((listen (lambda (endpoint)
                   (native (lambda (ticket)
                             (host-start-listen ticket
                                                (address-number endpoint)
                                                (Endpoint-port endpoint)
                                                accept-backlog))
                           listening)))
         (connect (lambda (endpoint)
                    (native (lambda (ticket)
                              (host-start-connect ticket
                                                  (address-number endpoint)
                                                  (Endpoint-port endpoint)))
                            connected)))
         (accept (lambda (listener)
                   (native (lambda (ticket) (host-start-accept ticket (listener-handle listener)))
                           connected)))
         (read (lambda (connection maximum)
                 (if (and (>= maximum 1) (<= maximum read-limit))
                     (native (lambda (ticket)
                               (host-start-read ticket (connection-handle connection) maximum))
                             held-read)
                     (Err (SocketError "EINVAL")))))
         (write (lambda (connection bytes)
                  (native (lambda (ticket)
                            (host-start-write ticket (connection-handle connection) bytes))
                          count)))
         (finish-connection
          (lambda (connection grace)
            (if (>= grace 0)
                (native (lambda (ticket)
                          (host-start-finish-connection ticket
                                                        (connection-handle connection)
                                                        grace))
                        done)
                (Err (SocketError "EINVAL")))))
         (close-listener (lambda (listener)
                           (answered (host-close-tcp (listener-handle listener)) done)))
         (close-connection (lambda (connection)
                             (answered (host-close-tcp (connection-handle connection)) done))))))

    (effect udp
      ((bind (-> Endpoint (Result UdpSocket SocketError) ! tasks))
       (send (-> UdpSocket Endpoint Bytes (Result I32 SocketError) ! tasks))
       (receive (-> UdpSocket I32 (Result Datagram SocketError) ! tasks))
       (close-udp (-> UdpSocket (Result Unit SocketError))))
      (default
        ((bind (lambda (endpoint)
                 (native (lambda (ticket)
                           (host-start-bind ticket
                                            (address-number endpoint)
                                            (Endpoint-port endpoint)
                                            datagram-queue))
                         bound)))
         ;; Port 0 names no peer, though a socket may bind to it.
         (send (lambda (socket peer bytes)
                 (cond ((= (Endpoint-port peer) 0) (Err (SocketError "EINVAL")))
                       ((> (vector-length bytes) (i32->i64 datagram-limit))
                        (Err (SocketError "EMSGSIZE")))
                       (else (native (lambda (ticket)
                                       (host-start-send ticket
                                                        (udp-handle socket)
                                                        (address-number peer)
                                                        (Endpoint-port peer)
                                                        bytes))
                                     count)))))
         (receive (lambda (socket maximum)
                    (if (and (>= maximum 0) (<= maximum datagram-limit))
                        (match (native (lambda (ticket)
                                         (host-start-receive ticket (udp-handle socket) maximum))
                                       held-datagram)
                          ((Ok datagram) datagram)
                          ((Err error) (Err error)))
                        (Err (SocketError "EINVAL")))))
         (close-udp (lambda (socket)
                      (answered (host-close-udp (udp-handle socket)) done))))))

    ;; ---- Native tokens ----

    ;; These types are private to the native binding. A mock token reaching
    ;; that binding crosses as handle 0, which the host refuses with EBADF.
    (struct NativeListener
      ((handle I32)))

    (struct NativeConnection
      ((handle I32)))

    (struct NativeUdpSocket
      ((handle I32)))

    (: listener-handle (-> Listener I32))
    (define (listener-handle listener)
      (let ((token (Listener-token listener)))
        (match (try-convert token NativeListener)
          ((Ok native) (NativeListener-handle native))
          ((Err _) 0))))

    (: connection-handle (-> Connection I32))
    (define (connection-handle connection)
      (let ((token (Connection-token connection)))
        (match (try-convert token NativeConnection)
          ((Ok native) (NativeConnection-handle native))
          ((Err _) 0))))

    (: udp-handle (-> UdpSocket I32))
    (define (udp-handle socket)
      (let ((token (UdpSocket-token socket)))
        (match (try-convert token NativeUdpSocket)
          ((Ok native) (NativeUdpSocket-handle native))
          ((Err _) 0))))

    ;; An endpoint crosses to the host as two I32s, its port and its
    ;; address, whose octets the host reads as the I32's unsigned bits.
    (: address-number (-> Endpoint I32))
    (define (address-number endpoint)
      (i64->i32 (Ipv4Endpoint-address endpoint)))

    ;; ---- Native answers ----

    ;; An operation that waits on the host: `start` starts it under its
    ;; ticket, and `success` reads its answer when it did not fail.
    (: native (All (T) (-> (-> I64 Unit) (-> I32 T) (Result T SocketError) ! tasks)))
    (define (native start success)
      (through-host start (lambda (ticket) (answered (host-finish ticket) success))))

    ;; What the host holds for an answer is read before the next host call
    ;; ((snail runtime native socket) has the table); a failure holds its
    ;; code. A handle in an answer is the shell's from then on.
    (: answered (All (T) (-> I32 (-> I32 T) (Result T SocketError))))
    (define (answered answer success)
      (if (< answer 0)
          (Err (SocketError (held-text 0)))
          (Ok (success answer))))

    (: held-bytes (-> I32 Bytes))
    (define (held-bytes position)
      (vector-generate (i32->i64 (host-held-length position))
                       (lambda (index) (i32->u8 (host-held-byte position (i64->i32 index))))))

    ;; Error codes and addresses are ASCII.
    (: held-text (-> I32 String))
    (define (held-text position)
      (string-generate (i32->i64 (host-held-length position))
                       (lambda (index) (i32->char (host-held-byte position (i64->i32 index))))))

    (: listening (-> I32 Listener))
    (define (listening handle)
      (Listener (type-convert (NativeListener handle) Any) (host-held-number)))

    (: connected (-> I32 Connection))
    (define (connected handle)
      (Connection (type-convert (NativeConnection handle) Any)))

    (: bound (-> I32 UdpSocket))
    (define (bound handle)
      (UdpSocket (type-convert (NativeUdpSocket handle) Any) (host-held-number)))

    (: held-read (-> I32 (Option Bytes)))
    (define (held-read answer)
      (if (= answer 0) (None) (Some (held-bytes 0))))

    ;; Node names a datagram's sender by its dotted text, which `endpoint`
    ;; parses as it would any other.
    (: held-datagram (-> I32 (Result Datagram SocketError)))
    (define (held-datagram _)
      (match (endpoint (held-text 0) (host-held-number))
        ((Ok peer) (Ok (Datagram peer (held-bytes 1))))
        ((Err error) (Err error))))

    (: count (-> I32 I32))
    (define (count written) written)

    (: done (-> I32 Unit))
    (define (done _) (unit))))
