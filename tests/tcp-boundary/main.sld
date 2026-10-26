(import
 (lofi base)
 (lofi tcp))

(: require (All (T) (-> (Result T TcpError) T)))
(define (require result)
  (match result
    ((Ok value) value)
    ((Err error) (panic (TcpError-code error)))))

(: open (-> (Result Listener TcpError) ! tcp))
(define (open)
  (listen (Endpoint "127.0.0.1" 0)))

(: listener (-> (Result Listener TcpError) Listener))
(define (listener result) (require result))

(: port (-> Listener I32))
(define (port listener) (Listener-port listener))

(: dial (-> I32 (Result Connection TcpError) ! tcp))
(define (dial port)
  (connect (Endpoint "127.0.0.1" port)))

(: take (-> Listener (Result Connection TcpError) ! tcp))
(define (take listener) (accept listener))

(: connection (-> (Result Connection TcpError) Connection))
(define (connection result) (require result))

(: receive (-> Connection I32 (Result (Option Bytes) TcpError) ! tcp))
(define (receive connection count) (read connection count))

(: read-count (-> (Result (Option Bytes) TcpError) I32))
(define (read-count result)
  (match (require result)
    ((Some bytes) (i64->i32 (vector-length bytes)))
    ((None) -1)))

(: read-byte (-> (Result (Option Bytes) TcpError) I32 I32))
(define (read-byte result index)
  (match (require result)
    ((Some bytes) (u8->i32 (vector-ref bytes (i32->i64 index))))
    ((None) -1)))

(: bad-read? (-> (Result (Option Bytes) TcpError) Bool))
(define (bad-read? result)
  (match result
    ((Err error) (string=? (TcpError-code error) "EBADF"))
    ((Ok _) #f)))

(: send (-> Connection (Result I32 TcpError) ! tcp))
(define (send connection) (write connection #u8(0 255 128 1)))

(: written (-> (Result I32 TcpError) I32))
(define (written result) (require result))

(: overwrite (-> Bool ! tcp))
(define (overwrite)
  (match (write (Connection (type-convert (ann 1 I32) Any)) #u8(9 8 7))
    ((Err error) (string=? (TcpError-code error) "EBADF"))
    ((Ok _) #f)))

(: stop-listener (-> Listener Unit ! tcp))
(define (stop-listener listener) (require (close-listener listener)))

(: stop-connection (-> Connection Unit ! tcp))
(define (stop-connection connection) (require (close-connection connection)))

(expose open "open")
(expose listener "listener")
(expose port "port")
(expose dial "dial")
(expose take "take")
(expose connection "connection")
(expose receive "receive")
(expose read-count "read-count")
(expose read-byte "read-byte")
(expose bad-read? "bad-read")
(expose send "send")
(expose written "written")
(expose overwrite "overwrite")
(expose stop-listener "stop-listener")
(expose stop-connection "stop-connection")
