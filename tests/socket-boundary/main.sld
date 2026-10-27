(import
 (snail-core base)
 (rename (snail-core socket)
         (send udp-send)
         (receive udp-receive)))

(: require (All (T) (-> (Result T SocketError) T)))
(define (require result)
  (match result
    ((Ok value) value)
    ((Err error) (panic (SocketError-code error)))))

(: open (-> (Result Listener SocketError) ! tcp))
(define (open)
  (listen (Endpoint "127.0.0.1" 0)))

(: listener (-> (Result Listener SocketError) Listener))
(define (listener result) (require result))

(: port (-> Listener I32))
(define (port listener) (Listener-port listener))

(: dial (-> I32 (Result Connection SocketError) ! tcp))
(define (dial port)
  (connect (Endpoint "127.0.0.1" port)))

(: take (-> Listener (Result Connection SocketError) ! tcp))
(define (take listener) (accept listener))

(: connection (-> (Result Connection SocketError) Connection))
(define (connection result) (require result))

(: receive (-> Connection I32 (Result (Option Bytes) SocketError) ! tcp))
(define (receive connection count) (read connection count))

(: read-count (-> (Result (Option Bytes) SocketError) I32))
(define (read-count result)
  (match (require result)
    ((Some bytes) (i64->i32 (vector-length bytes)))
    ((None) -1)))

(: read-byte (-> (Result (Option Bytes) SocketError) I32 I32))
(define (read-byte result index)
  (match (require result)
    ((Some bytes) (u8->i32 (vector-ref bytes (i32->i64 index))))
    ((None) -1)))

(: bad-read? (-> (Result (Option Bytes) SocketError) Bool))
(define (bad-read? result)
  (match result
    ((Err error) (string=? (SocketError-code error) "EBADF"))
    ((Ok _) #f)))

(: send (-> Connection (Result I32 SocketError) ! tcp))
(define (send connection) (write connection #u8(0 255 128 1)))

(: written (-> (Result I32 SocketError) I32))
(define (written result) (require result))

(: overwrite (-> Bool ! tcp))
(define (overwrite)
  (match (write (Connection (type-convert (ann 1 I32) Any)) #u8(9 8 7))
    ((Err error) (string=? (SocketError-code error) "EBADF"))
    ((Ok _) #f)))

(: stop-listener (-> Listener Unit ! tcp))
(define (stop-listener listener) (require (close-listener listener)))

(: stop-connection (-> Connection Unit ! tcp))
(define (stop-connection connection) (require (close-connection connection)))

(: finish (-> Connection I32 (Result Unit SocketError) ! tcp))
(define (finish connection grace) (finish-connection connection grace))

(: finished? (-> (Result Unit SocketError) Bool))
(define (finished? result)
  (match result ((Ok _) #t) ((Err _) #f)))

(: timed-out? (-> (Result Unit SocketError) Bool))
(define (timed-out? result)
  (match result
    ((Err error) (string=? (SocketError-code error) "ETIMEDOUT"))
    ((Ok _) #f)))

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
(expose finish "finish")
(expose finished? "finished")
(expose timed-out? "timed-out")

(: open-udp (-> UdpSocket ! udp))
(define (open-udp) (require (bind (Endpoint "127.0.0.1" 0))))

(: udp-port (-> UdpSocket I32))
(define (udp-port socket) (UdpSocket-port socket))

(: send-udp (-> UdpSocket I32 (Result I32 SocketError) ! udp))
(define (send-udp socket port)
  (udp-send socket (Endpoint "127.0.0.1" port) #u8(0 255 128 1)))

(: receive-udp (-> UdpSocket I32 (Result Datagram SocketError) ! udp))
(define (receive-udp socket count) (udp-receive socket count))

(: packet-port (-> (Result Datagram SocketError) I32))
(define (packet-port result) (Endpoint-port (Datagram-peer (require result))))

(: packet-size (-> (Result Datagram SocketError) I32))
(define (packet-size result) (i64->i32 (vector-length (Datagram-bytes (require result)))))

(: packet-byte (-> (Result Datagram SocketError) I32 I32))
(define (packet-byte result index)
  (u8->i32 (vector-ref (Datagram-bytes (require result)) (i32->i64 index))))

(: stop-udp (-> UdpSocket Unit ! udp))
(define (stop-udp socket) (require (close-udp socket)))

(extern stage "snail.test" "stage" (-> Bytes I32))
(: overwrite-stage (-> I32))
(define (overwrite-stage) (stage #u8(9 8 7)))

(expose open-udp "open-udp")
(expose udp-port "udp-port")
(expose send-udp "send-udp")
(expose receive-udp "receive-udp")
(expose packet-port "packet-port")
(expose packet-size "packet-size")
(expose packet-byte "packet-byte")
(expose stop-udp "stop-udp")
(expose overwrite-stage "overwrite-stage")
