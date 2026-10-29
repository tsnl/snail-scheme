;; Concrete TCP and UDP operations. A handler can replace either effect in a
;; test. By default, an operation that waits starts on the native host and
;; waits for its completion as a task does, by ticket ((snail shell task)'s
;; `through-host`), so each such operation's latent row names `tasks`.
(define-library (snail shell socket)
  (export
   tcp listen connect accept read write finish-connection close-listener close-connection
   udp bind send receive close-udp
   Endpoint Endpoint-address Endpoint-port
   Listener Listener-token Listener-port
   Connection Connection-token
   UdpSocket UdpSocket-token UdpSocket-port
   Datagram Datagram-peer Datagram-bytes
   SocketError SocketError-code)
  (import
   (snail core base)
   (only (snail shell task) tasks through-host))
  (begin

    ;; ---- Public values ----

    (struct Endpoint
      ((address String)
       (port I32)))

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
      (host "snail.runtime.native.socket"
            ((close-listener "close-listener")
             (close-connection "close-connection")))
      (default
        ((listen (lambda (endpoint)
                   (through-host (lambda (ticket) (start-listen ticket endpoint)) finish-listen)))
         (connect (lambda (endpoint)
                    (through-host (lambda (ticket) (start-connect ticket endpoint))
                                  finish-connect)))
         (accept (lambda (listener)
                   (through-host (lambda (ticket) (start-accept ticket listener)) finish-accept)))
         (read (lambda (connection maximum)
                 (through-host (lambda (ticket) (start-read ticket connection maximum))
                               finish-read)))
         (write (lambda (connection bytes)
                  (through-host (lambda (ticket) (start-write ticket connection bytes))
                                finish-write)))
         (finish-connection
          (lambda (connection grace)
            (through-host (lambda (ticket) (start-finish-connection ticket connection grace))
                          finish-finish-connection))))))

    (effect udp
      ((bind (-> Endpoint (Result UdpSocket SocketError) ! tasks))
       (send (-> UdpSocket Endpoint Bytes (Result I32 SocketError) ! tasks))
       (receive (-> UdpSocket I32 (Result Datagram SocketError) ! tasks))
       (close-udp (-> UdpSocket (Result Unit SocketError))))
      (host "snail.runtime.native.socket"
            ((close-udp "close-udp")))
      (default
        ((bind (lambda (endpoint)
                 (through-host (lambda (ticket) (start-bind ticket endpoint)) finish-bind)))
         (send (lambda (socket peer bytes)
                 (through-host (lambda (ticket) (start-send ticket socket peer bytes))
                               finish-send)))
         (receive (lambda (socket maximum)
                    (through-host (lambda (ticket) (start-receive ticket socket maximum))
                                  finish-receive))))))

    ;; ---- Native waits ----

    ;; Each operation that waits starts on the host, which reads its
    ;; arguments at once, and finishes with the result the host built for
    ;; its ticket. Both halves return at once.
    (extern start-listen "snail.runtime.native.socket" "start-listen" (-> I64 Endpoint Unit))
    (extern finish-listen
            "snail.runtime.native.socket"
            "finish-listen"
            (-> I64 (Result Listener SocketError)))
    (extern start-connect "snail.runtime.native.socket" "start-connect" (-> I64 Endpoint Unit))
    (extern finish-connect
            "snail.runtime.native.socket"
            "finish-connect"
            (-> I64 (Result Connection SocketError)))
    (extern start-accept "snail.runtime.native.socket" "start-accept" (-> I64 Listener Unit))
    (extern finish-accept
            "snail.runtime.native.socket"
            "finish-accept"
            (-> I64 (Result Connection SocketError)))
    (extern start-read "snail.runtime.native.socket" "start-read" (-> I64 Connection I32 Unit))
    (extern finish-read
            "snail.runtime.native.socket"
            "finish-read"
            (-> I64 (Result (Option Bytes) SocketError)))
    (extern start-write "snail.runtime.native.socket" "start-write" (-> I64 Connection Bytes Unit))
    (extern finish-write
            "snail.runtime.native.socket"
            "finish-write"
            (-> I64 (Result I32 SocketError)))
    (extern start-finish-connection
            "snail.runtime.native.socket"
            "start-finish-connection"
            (-> I64 Connection I32 Unit))
    (extern finish-finish-connection
            "snail.runtime.native.socket"
            "finish-finish-connection"
            (-> I64 (Result Unit SocketError)))
    (extern start-bind "snail.runtime.native.socket" "start-bind" (-> I64 Endpoint Unit))
    (extern finish-bind
            "snail.runtime.native.socket"
            "finish-bind"
            (-> I64 (Result UdpSocket SocketError)))
    (extern start-send
            "snail.runtime.native.socket"
            "start-send"
            (-> I64 UdpSocket Endpoint Bytes Unit))
    (extern finish-send
            "snail.runtime.native.socket"
            "finish-send"
            (-> I64 (Result I32 SocketError)))
    (extern start-receive "snail.runtime.native.socket" "start-receive" (-> I64 UdpSocket I32 Unit))
    (extern finish-receive
            "snail.runtime.native.socket"
            "finish-receive"
            (-> I64 (Result Datagram SocketError)))

    ;; ---- Native tokens ----

    ;; These types are private to the native binding. A mock token reaching
    ;; that binding becomes EBADF instead of being cast to a native handle.
    (struct NativeListener
      ((handle I32)))

    (struct NativeConnection
      ((handle I32)))

    (struct NativeUdpSocket
      ((handle I32)))

    (: listener-handle (-> Listener I32))
    (define (listener-handle listener)
      (let ((token (Listener-token listener)))
        (if (type-test token NativeListener)
            (NativeListener-handle (type-convert token NativeListener))
            0)))

    (: connection-handle (-> Connection I32))
    (define (connection-handle connection)
      (let ((token (Connection-token connection)))
        (if (type-test token NativeConnection)
            (NativeConnection-handle (type-convert token NativeConnection))
            0)))

    (: udp-handle (-> UdpSocket I32))
    (define (udp-handle socket)
      (let ((token (UdpSocket-token socket)))
        (if (type-test token NativeUdpSocket)
            (NativeUdpSocket-handle (type-convert token NativeUdpSocket))
            0)))

    (: address-length (-> Endpoint I32))
    (define (address-length endpoint)
      (i64->i32 (min 16 (string-length (Endpoint-address endpoint)))))

    (: address-character (-> Endpoint I32 Char))
    (define (address-character endpoint index)
      (string-ref (Endpoint-address endpoint) (i32->i64 index)))

    (: endpoint-port (-> Endpoint I32))
    (define (endpoint-port endpoint)
      (Endpoint-port endpoint))

    (expose listener-handle "tcp:listener-handle")
    (expose connection-handle "tcp:connection-handle")
    (expose udp-handle "udp:socket-handle")
    (expose endpoint-port "socket:endpoint-port")
    (expose address-length "socket:address-length")
    (expose address-character "socket:address-character")

    ;; ---- Host result construction ----

    ;; JavaScript carries GC references opaquely. These synchronous helpers
    ;; run only inside a finish, which the waiting task calls.
    (: buffer (-> I32 (Array U8) ! mut))
    (define (buffer count)
      (make-array (i32->i64 count) (i32->u8 0)))

    (: put! (-> (Array U8) I32 I32 Unit ! mut))
    (define (put! target index byte)
      (array-set! target (i32->i64 index) (i32->u8 byte)))

    (: ascii-text (-> (Array U8) String ! mut))
    (define (ascii-text bytes)
      (string-generate (array-length bytes)
                       (lambda (index) (i32->char (u8->i32 (array-ref bytes index))))))

    (: error-code (-> (Array U8) SocketError ! mut))
    (define (error-code bytes)
      (SocketError (ascii-text bytes)))

    (: listening (-> I32 I32 (Result Listener SocketError)))
    (define (listening handle port)
      (Ok (Listener (type-convert (NativeListener handle) Any) port)))

    (: connected (-> I32 (Result Connection SocketError)))
    (define (connected handle)
      (Ok (Connection (type-convert (NativeConnection handle) Any))))

    (: bound (-> I32 I32 (Result UdpSocket SocketError)))
    (define (bound handle port)
      (Ok (UdpSocket (type-convert (NativeUdpSocket handle) Any) port)))

    (: received-datagram (-> (Array U8) I32 (Array U8) (Result Datagram SocketError) ! mut))
    (define (received-datagram address port bytes)
      (Ok (Datagram (Endpoint (ascii-text address) port) (array->vector bytes))))

    (: received (-> (Array U8) (Result (Option Bytes) SocketError) ! mut))
    (define (received bytes)
      (Ok (Some (array->vector bytes))))

    (: eof (-> (Result (Option Bytes) SocketError)))
    (define (eof)
      (Ok (None)))

    (: written (-> I32 (Result I32 SocketError)))
    (define (written count)
      (Ok count))

    (: closed (-> (Result Unit SocketError)))
    (define (closed)
      (Ok (unit)))

    ;; Each Result has its own concrete Wasm type, including its Err variant.
    (: listen-error (-> SocketError (Result Listener SocketError)))
    (define (listen-error error) (Err error))

    (: connection-error (-> SocketError (Result Connection SocketError)))
    (define (connection-error error) (Err error))

    (: bind-error (-> SocketError (Result UdpSocket SocketError)))
    (define (bind-error error) (Err error))

    (: receive-error (-> SocketError (Result Datagram SocketError)))
    (define (receive-error error) (Err error))

    (: read-error (-> SocketError (Result (Option Bytes) SocketError)))
    (define (read-error error) (Err error))

    (: write-error (-> SocketError (Result I32 SocketError)))
    (define (write-error error) (Err error))

    (: close-error (-> SocketError (Result Unit SocketError)))
    (define (close-error error) (Err error))

    (expose buffer "socket:buffer")
    (expose put! "socket:put")
    (expose error-code "socket:error-code")
    (expose listening "tcp:listening")
    (expose connected "tcp:connected")
    (expose bound "udp:bound")
    (expose received-datagram "udp:received")
    (expose received "tcp:received")
    (expose eof "tcp:eof")
    (expose written "socket:written")
    (expose closed "socket:closed")
    (expose listen-error "tcp:listen-error")
    (expose connection-error "tcp:connection-error")
    (expose bind-error "udp:bind-error")
    (expose receive-error "udp:receive-error")
    (expose read-error "tcp:read-error")
    (expose write-error "socket:write-error")
    (expose close-error "socket:close-error")))
