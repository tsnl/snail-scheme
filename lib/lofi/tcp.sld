;; Concrete TCP operations. A handler can replace the effect in a test;
;; the native runner supplies the default implementation through JSPI.
(define-library (lofi tcp)
  (export
   tcp listen connect accept read write close-listener close-connection
   Endpoint Endpoint-address Endpoint-port
   Listener Listener-token Listener-port
   Connection Connection-token
   TcpError TcpError-code)
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

    (struct TcpError
      ((code String)))

    (effect tcp
      ((listen (-> Endpoint (Result Listener TcpError)))
       (connect (-> Endpoint (Result Connection TcpError)))
       (accept (-> Listener (Result Connection TcpError)))
       (read (-> Connection I32 (Result (Option Bytes) TcpError)))
       (write (-> Connection Bytes (Result I32 TcpError)))
       (close-listener (-> Listener (Result Unit TcpError)))
       (close-connection (-> Connection (Result Unit TcpError))))
      (host "snail.tcp"
            ((listen "listen")
             (connect "connect")
             (accept "accept")
             (read "read")
             (write "write")
             (close-listener "close-listener")
             (close-connection "close-connection"))))

    ;; ---- Native tokens ----

    ;; These types are private to the native binding. A mock token reaching
    ;; that binding becomes EBADF instead of being cast to a native handle.
    (struct NativeListener
      ((handle I32)))

    (struct NativeConnection
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
    (expose endpoint-port "tcp:endpoint-port")
    (expose address-length "tcp:address-length")
    (expose address-character "tcp:address-character")

    ;; ---- Host result construction ----

    ;; JavaScript carries GC references opaquely. These synchronous helpers
    ;; run only after the waiting task reacquires the execution permit.
    (: buffer (-> I32 (Array U8) ! mut))
    (define (buffer count)
      (make-array (i32->i64 count) (i32->u8 0)))

    (: put! (-> (Array U8) I32 I32 Unit ! mut))
    (define (put! target index byte)
      (array-set! target (i32->i64 index) (i32->u8 byte)))

    (: error-code (-> (Array U8) TcpError ! mut))
    (define (error-code bytes)
      (TcpError (string-generate (array-length bytes)
                                 (lambda (index) (i32->char (u8->i32 (array-ref bytes index)))))))

    (: listening (-> I32 I32 (Result Listener TcpError)))
    (define (listening handle port)
      (Ok (Listener (type-convert (NativeListener handle) Any) port)))

    (: connected (-> I32 (Result Connection TcpError)))
    (define (connected handle)
      (Ok (Connection (type-convert (NativeConnection handle) Any))))

    (: received (-> (Array U8) (Result (Option Bytes) TcpError) ! mut))
    (define (received bytes)
      (Ok (Some (array->vector bytes))))

    (: eof (-> (Result (Option Bytes) TcpError)))
    (define (eof)
      (Ok (None)))

    (: written (-> I32 (Result I32 TcpError)))
    (define (written count)
      (Ok count))

    (: closed (-> (Result Unit TcpError)))
    (define (closed)
      (Ok (unit)))

    ;; Each Result has its own concrete Wasm type, including its Err variant.
    (: listen-error (-> TcpError (Result Listener TcpError)))
    (define (listen-error error) (Err error))

    (: connection-error (-> TcpError (Result Connection TcpError)))
    (define (connection-error error) (Err error))

    (: read-error (-> TcpError (Result (Option Bytes) TcpError)))
    (define (read-error error) (Err error))

    (: write-error (-> TcpError (Result I32 TcpError)))
    (define (write-error error) (Err error))

    (: close-error (-> TcpError (Result Unit TcpError)))
    (define (close-error error) (Err error))

    (expose buffer "tcp:buffer")
    (expose put! "tcp:put")
    (expose error-code "tcp:error-code")
    (expose listening "tcp:listening")
    (expose connected "tcp:connected")
    (expose received "tcp:received")
    (expose eof "tcp:eof")
    (expose written "tcp:written")
    (expose closed "tcp:closed")
    (expose listen-error "tcp:listen-error")
    (expose connection-error "tcp:connection-error")
    (expose read-error "tcp:read-error")
    (expose write-error "tcp:write-error")
    (expose close-error "tcp:close-error")))
