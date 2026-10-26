;; Concrete TCP and UDP operations. A handler can replace either effect in a test;
;; the native runner supplies the default implementation through JSPI.
(define-library (lofi socket)
  (export
   tcp listen connect accept read write close-listener close-connection
   udp bind send receive close-udp
   Endpoint Endpoint-address Endpoint-port
   Listener Listener-token Listener-port
   Connection Connection-token
   UdpSocket UdpSocket-token UdpSocket-port
   Datagram Datagram-peer Datagram-bytes
   SocketError SocketError-code)
  (import
   (lofi base))
  (begin

    ;; ---- Public values ----

    (struct Endpoint
      ((address String)
       (port I32)))

    ;; Tokens belong to the effect handler that created them. Any keeps a
    ;; native endpoint local (!Send, !Sync), and lets tests use their own tokens.
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
      ((listen (-> Endpoint (Result Listener SocketError)))
       (connect (-> Endpoint (Result Connection SocketError)))
       (accept (-> Listener (Result Connection SocketError)))
       (read (-> Connection I32 (Result (Option Bytes) SocketError)))
       (write (-> Connection Bytes (Result I32 SocketError)))
       (close-listener (-> Listener (Result Unit SocketError)))
       (close-connection (-> Connection (Result Unit SocketError))))
      (host "snail.socket"
            ((listen "listen")
             (connect "connect")
             (accept "accept")
             (read "read")
             (write "write")
             (close-listener "close-listener")
             (close-connection "close-connection"))))

    (effect udp
      ((bind (-> Endpoint (Result UdpSocket SocketError)))
       (send (-> UdpSocket Endpoint Bytes (Result I32 SocketError)))
       (receive (-> UdpSocket I32 (Result Datagram SocketError)))
       (close-udp (-> UdpSocket (Result Unit SocketError))))
      (host "snail.socket"
            ((bind "bind")
             (send "send")
             (receive "receive")
             (close-udp "close-udp"))))

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
    ;; run only after the waiting task reacquires the execution permit.
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
