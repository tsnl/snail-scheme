(import
 (snail core base)
 (only (snail shell task) tasks dispatch-task)
 (rename (snail shell socket)
         (send udp-send)
         (receive udp-receive)))

;; ---- Requests ----

;; Each operation that waits runs as a task, as a program's would:
;; `begin-NAME` dispatches one and answers its task's id, and once
;; `answered` holds for that id, `answer` is the operation's result, as an
;; Any, which the accessors below convert back. A task that traps never
;; answers; the host reports the trap under the same id.
(: slots (Ref (List (Pair I64 (Ref (Option Any))))))
(define slots (ref (Nil)))

(: request (-> (FnOnce Any ! tcp udp tasks) I64 ! mut tcp udp))
(define (request work)
  (let* ((slot (ref (ann (None) (Option Any))))
         (id (dispatch-task (once (lambda () (ref-set! slot (Some (work))))))))
    (ref-set! slots (Cons (Pair id slot) (ref-get slots)))
    id))

(: slot (-> I64 (Ref (Option Any)) ! mut))
(define (slot id)
  (match (assoc-ref (ref-get slots) id)
    ((Some found) found)
    ((None) (panic "no such request"))))

(: answered? (-> I64 Bool ! mut))
(define (answered? id)
  (match (ref-get (slot id))
    ((Some _) #t)
    ((None) #f)))

(: answer (-> I64 Any ! mut))
(define (answer id)
  (match (ref-get (slot id))
    ((Some result) result)
    ((None) (panic "the request has not answered"))))

(: truth (-> Any I32))
(define (truth answer)
  (if (type-convert answer Bool) 1 0))

(expose answered? "answered")
(expose answer "answer")
(expose truth "truth")

;; ---- Operations ----

(: require (All (T) (-> (Result T SocketError) T)))
(define (require result)
  (match result
    ((Ok value) value)
    ((Err error) (panic (SocketError-code error)))))

(: open (-> (Result Listener SocketError) ! tcp tasks))
(define (open)
  (listen (require (endpoint "127.0.0.1" 0))))

(: listener (-> Any Listener))
(define (listener answer)
  (require (type-convert answer (Result Listener SocketError))))

(: port (-> Listener I32))
(define (port listener) (Listener-port listener))

(: dial (-> I32 (Result Connection SocketError) ! tcp tasks))
(define (dial port)
  (connect (require (endpoint "127.0.0.1" port))))

(: take (-> Listener (Result Connection SocketError) ! tcp tasks))
(define (take listener) (accept listener))

(: connection (-> Any Connection))
(define (connection answer)
  (require (type-convert answer (Result Connection SocketError))))

(: receive (-> Connection I32 (Result (Option Bytes) SocketError) ! tcp tasks))
(define (receive connection count) (read connection count))

(: read-count (-> Any I32))
(define (read-count answer)
  (match (require (type-convert answer (Result (Option Bytes) SocketError)))
    ((Some bytes) (i64->i32 (vector-length bytes)))
    ((None) -1)))

(: read-byte (-> Any I32 I32))
(define (read-byte answer index)
  (match (require (type-convert answer (Result (Option Bytes) SocketError)))
    ((Some bytes) (u8->i32 (vector-ref bytes (i32->i64 index))))
    ((None) -1)))

(: bad-read? (-> Any Bool))
(define (bad-read? answer)
  (match (type-convert answer (Result (Option Bytes) SocketError))
    ((Err error) (string=? (SocketError-code error) "EBADF"))
    ((Ok _) #f)))

(: send (-> Connection (Result I32 SocketError) ! tcp tasks))
(define (send connection) (write connection #u8(0 255 128 1)))

(: written (-> Any I32))
(define (written answer)
  (require (type-convert answer (Result I32 SocketError))))

(: overwrite (-> Bool ! tcp tasks))
(define (overwrite)
  (match (write (Connection (type-convert (ann 1 I32) Any)) #u8(9 8 7))
    ((Err error) (string=? (SocketError-code error) "EBADF"))
    ((Ok _) #f)))

(: stop-listener (-> Listener Unit ! tcp))
(define (stop-listener listener) (require (close-listener listener)))

(: stop-connection (-> Connection Unit ! tcp))
(define (stop-connection connection) (require (close-connection connection)))

(: finish (-> Connection I32 (Result Unit SocketError) ! tcp tasks))
(define (finish connection grace) (finish-connection connection grace))

(: finished? (-> Any Bool))
(define (finished? answer)
  (match (type-convert answer (Result Unit SocketError))
    ((Ok _) #t)
    ((Err _) #f)))

(: timed-out? (-> Any Bool))
(define (timed-out? answer)
  (match (type-convert answer (Result Unit SocketError))
    ((Err error) (string=? (SocketError-code error) "ETIMEDOUT"))
    ((Ok _) #f)))

(: begin-open (-> I64 ! mut tcp udp))
(define (begin-open)
  (request (once (lambda () (type-convert (open) Any)))))

(: begin-dial (-> I32 I64 ! mut tcp udp))
(define (begin-dial port)
  (request (once (lambda () (type-convert (dial port) Any)))))

(: begin-take (-> Listener I64 ! mut tcp udp))
(define (begin-take listener)
  (request (once (lambda () (type-convert (take listener) Any)))))

(: begin-receive (-> Connection I32 I64 ! mut tcp udp))
(define (begin-receive connection count)
  (request (once (lambda () (type-convert (receive connection count) Any)))))

(: begin-send (-> Connection I64 ! mut tcp udp))
(define (begin-send connection)
  (request (once (lambda () (type-convert (send connection) Any)))))

(: begin-overwrite (-> I64 ! mut tcp udp))
(define (begin-overwrite)
  (request (once (lambda () (type-convert (overwrite) Any)))))

(: begin-finish (-> Connection I32 I64 ! mut tcp udp))
(define (begin-finish connection grace)
  (request (once (lambda () (type-convert (finish connection grace) Any)))))

(expose begin-open "begin-open")
(expose listener "listener")
(expose port "port")
(expose begin-dial "begin-dial")
(expose begin-take "begin-take")
(expose connection "connection")
(expose begin-receive "begin-receive")
(expose read-count "read-count")
(expose read-byte "read-byte")
(expose bad-read? "bad-read")
(expose begin-send "begin-send")
(expose written "written")
(expose begin-overwrite "begin-overwrite")
(expose stop-listener "stop-listener")
(expose stop-connection "stop-connection")
(expose begin-finish "begin-finish")
(expose finished? "finished")
(expose timed-out? "timed-out")

(: open-udp (-> UdpSocket ! udp tasks))
(define (open-udp) (require (bind (require (endpoint "127.0.0.1" 0)))))

(: udp-socket (-> Any UdpSocket))
(define (udp-socket answer)
  (type-convert answer UdpSocket))

(: udp-port (-> UdpSocket I32))
(define (udp-port socket) (UdpSocket-port socket))

(: send-udp (-> UdpSocket I32 (Result I32 SocketError) ! udp tasks))
(define (send-udp socket port)
  (udp-send socket (require (endpoint "127.0.0.1" port)) #u8(0 255 128 1)))

(: receive-udp (-> UdpSocket I32 (Result Datagram SocketError) ! udp tasks))
(define (receive-udp socket count) (udp-receive socket count))

(: datagram (-> Any Datagram))
(define (datagram answer)
  (require (type-convert answer (Result Datagram SocketError))))

(: packet-port (-> Any I32))
(define (packet-port answer) (Endpoint-port (Datagram-peer (datagram answer))))

(: packet-size (-> Any I32))
(define (packet-size answer) (i64->i32 (vector-length (Datagram-bytes (datagram answer)))))

(: packet-byte (-> Any I32 I32))
(define (packet-byte answer index)
  (u8->i32 (vector-ref (Datagram-bytes (datagram answer)) (i32->i64 index))))

(: stop-udp (-> UdpSocket Unit ! udp))
(define (stop-udp socket) (require (close-udp socket)))

(: begin-open-udp (-> I64 ! mut tcp udp))
(define (begin-open-udp)
  (request (once (lambda () (type-convert (open-udp) Any)))))

(: begin-send-udp (-> UdpSocket I32 I64 ! mut tcp udp))
(define (begin-send-udp socket port)
  (request (once (lambda () (type-convert (send-udp socket port) Any)))))

(: begin-receive-udp (-> UdpSocket I32 I64 ! mut tcp udp))
(define (begin-receive-udp socket count)
  (request (once (lambda () (type-convert (receive-udp socket count) Any)))))

(expose begin-open-udp "begin-open-udp")
(expose udp-socket "udp-socket")
(expose udp-port "udp-port")
(expose begin-send-udp "begin-send-udp")
(expose begin-receive-udp "begin-receive-udp")
(expose packet-port "packet-port")
(expose packet-size "packet-size")
(expose packet-byte "packet-byte")
(expose stop-udp "stop-udp")
