(import
 (snail core base)
 (only (snail shell task) tasks dispatch-task)
 (rename (snail shell socket)
         (send udp-send)
         (receive udp-receive)))

;; A mismatch here is a broken test-host invariant. Guest conversions that
;; are expected to fail use dyn-cast handlers in the dedicated fixtures.
(define-syntax fixture-convert
  (syntax-rules ()
    ((_ value target)
     (match (try-convert value target)
       ((Ok checked) checked)
       ((Err _) (panic "fixture payload has the wrong type"))))))


;; ---- Requests ----

;; Each operation that waits runs as a task, as a program's would:
;; `begin-NAME` dispatches one and answers its task's id, and once
;; `answered` holds for that id, `answer` is the operation's result, as an
;; Any, which the accessors below convert back. A task that traps never
;; answers; the host reports the trap under the same id.
(: slots (Ref (List (Pair I64 (Ref (Option Any))))))
(define slots (ref (Nil)))

(: request (impl (Fn (dyn (FnOnce -> Any ! tcp udp tasks)) -> I64 ! mut tcp udp)))
(define (request work)
  (let* ((slot (ref (ann (None) (Option Any))))
         (id (dispatch-task (once (lambda () (ref-set! slot (Some (work))))))))
    (ref-set! slots (Cons (Pair id slot) (ref-get slots)))
    id))

(: slot (impl (Fn I64 -> (Ref (Option Any)) ! mut)))
(define (slot id)
  (match (assoc-ref (ref-get slots) id)
    ((Some found) found)
    ((None) (panic "no such request"))))

(: answered? (impl (Fn I64 -> Bool ! mut)))
(define (answered? id)
  (match (ref-get (slot id))
    ((Some _) #t)
    ((None) #f)))

(: answer (impl (Fn I64 -> Any ! mut)))
(define (answer id)
  (match (ref-get (slot id))
    ((Some result) result)
    ((None) (panic "the request has not answered"))))

(: truth (impl (Fn Any -> I32)))
(define (truth answer)
  (if (fixture-convert answer Bool) 1 0))

(expose answered? "answered")
(expose answer "answer")
(expose truth "truth")

;; ---- Operations ----

(: require (All (T) (impl (Fn (Result T SocketError) -> T))))
(define (require result)
  (match result
    ((Ok value) value)
    ((Err error) (panic (::code error)))))

(: open (impl (Fn -> (Result Listener SocketError) ! tcp tasks)))
(define (open)
  (listen (require (endpoint "127.0.0.1" 0))))

(: listener (impl (Fn Any -> Listener)))
(define (listener answer)
  (require (fixture-convert answer (Result Listener SocketError))))

(: port (impl (Fn Listener -> I32)))
(define (port listener) (::port listener))

(: dial (impl (Fn I32 -> (Result Connection SocketError) ! tcp tasks)))
(define (dial port)
  (connect (require (endpoint "127.0.0.1" port))))

(: take (impl (Fn Listener -> (Result Connection SocketError) ! tcp tasks)))
(define (take listener) (accept listener))

(: connection (impl (Fn Any -> Connection)))
(define (connection answer)
  (require (fixture-convert answer (Result Connection SocketError))))

(: receive (impl (Fn Connection I32 -> (Result (Option Bytes) SocketError) ! tcp tasks)))
(define (receive connection count) (read connection count))

(: read-count (impl (Fn Any -> I32)))
(define (read-count answer)
  (match (require (fixture-convert answer (Result (Option Bytes) SocketError)))
    ((Some bytes) (i64->i32 (vector-length bytes)))
    ((None) -1)))

(: read-byte (impl (Fn Any I32 -> I32)))
(define (read-byte answer index)
  (match (require (fixture-convert answer (Result (Option Bytes) SocketError)))
    ((Some bytes) (u8->i32 (vector-ref bytes (i32->i64 index))))
    ((None) -1)))

(: bad-read? (impl (Fn Any -> Bool)))
(define (bad-read? answer)
  (match (fixture-convert answer (Result (Option Bytes) SocketError))
    ((Err error) (string=? (::code error) "EBADF"))
    ((Ok _) #f)))

(: send (impl (Fn Connection -> (Result I32 SocketError) ! tcp tasks)))
(define (send connection) (write connection #u8(0 255 128 1)))

(: written (impl (Fn Any -> I32)))
(define (written answer)
  (require (fixture-convert answer (Result I32 SocketError))))

(: overwrite (impl (Fn -> Bool ! tcp tasks)))
(define (overwrite)
  (match (write (Connection (type-convert (ann 1 I32) Any)) #u8(9 8 7))
    ((Err error) (string=? (::code error) "EBADF"))
    ((Ok _) #f)))

(: stop-listener (impl (Fn Listener -> Unit ! tcp)))
(define (stop-listener listener) (require (close-listener listener)))

(: stop-connection (impl (Fn Connection -> Unit ! tcp)))
(define (stop-connection connection) (require (close-connection connection)))

(: finish (impl (Fn Connection I32 -> (Result Unit SocketError) ! tcp tasks)))
(define (finish connection grace) (finish-connection connection grace))

(: finished? (impl (Fn Any -> Bool)))
(define (finished? answer)
  (match (fixture-convert answer (Result Unit SocketError))
    ((Ok _) #t)
    ((Err _) #f)))

(: timed-out? (impl (Fn Any -> Bool)))
(define (timed-out? answer)
  (match (fixture-convert answer (Result Unit SocketError))
    ((Err error) (string=? (::code error) "ETIMEDOUT"))
    ((Ok _) #f)))

(: begin-open (impl (Fn -> I64 ! mut tcp udp)))
(define (begin-open)
  (request (once (lambda () (type-convert (open) Any)))))

(: begin-dial (impl (Fn I32 -> I64 ! mut tcp udp)))
(define (begin-dial port)
  (request (once (lambda () (type-convert (dial port) Any)))))

(: begin-take (impl (Fn Listener -> I64 ! mut tcp udp)))
(define (begin-take listener)
  (request (once (lambda () (type-convert (take listener) Any)))))

(: begin-receive (impl (Fn Connection I32 -> I64 ! mut tcp udp)))
(define (begin-receive connection count)
  (request (once (lambda () (type-convert (receive connection count) Any)))))

(: begin-send (impl (Fn Connection -> I64 ! mut tcp udp)))
(define (begin-send connection)
  (request (once (lambda () (type-convert (send connection) Any)))))

(: begin-overwrite (impl (Fn -> I64 ! mut tcp udp)))
(define (begin-overwrite)
  (request (once (lambda () (type-convert (overwrite) Any)))))

(: begin-finish (impl (Fn Connection I32 -> I64 ! mut tcp udp)))
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

(: open-udp (impl (Fn -> UdpSocket ! udp tasks)))
(define (open-udp) (require (bind (require (endpoint "127.0.0.1" 0)))))

(: udp-socket (impl (Fn Any -> UdpSocket)))
(define (udp-socket answer)
  (fixture-convert answer UdpSocket))

(: udp-port (impl (Fn UdpSocket -> I32)))
(define (udp-port socket) (::port socket))

(: send-udp (impl (Fn UdpSocket I32 -> (Result I32 SocketError) ! udp tasks)))
(define (send-udp socket port)
  (udp-send socket (require (endpoint "127.0.0.1" port)) #u8(0 255 128 1)))

(: receive-udp (impl (Fn UdpSocket I32 -> (Result Datagram SocketError) ! udp tasks)))
(define (receive-udp socket count) (udp-receive socket count))

(: datagram (impl (Fn Any -> Datagram)))
(define (datagram answer)
  (require (fixture-convert answer (Result Datagram SocketError))))

(: packet-port (impl (Fn Any -> I32)))
(define (packet-port answer) (Endpoint-port (::peer (datagram answer))))

(: packet-size (impl (Fn Any -> I32)))
(define (packet-size answer) (i64->i32 (vector-length (::bytes (datagram answer)))))

(: packet-byte (impl (Fn Any I32 -> I32)))
(define (packet-byte answer index)
  (u8->i32 (vector-ref (::bytes (datagram answer)) (i32->i64 index))))

(: stop-udp (impl (Fn UdpSocket -> Unit ! udp)))
(define (stop-udp socket) (require (close-udp socket)))

(: begin-open-udp (impl (Fn -> I64 ! mut tcp udp)))
(define (begin-open-udp)
  (request (once (lambda () (type-convert (open-udp) Any)))))

(: begin-send-udp (impl (Fn UdpSocket I32 -> I64 ! mut tcp udp)))
(define (begin-send-udp socket port)
  (request (once (lambda () (type-convert (send-udp socket port) Any)))))

(: begin-receive-udp (impl (Fn UdpSocket I32 -> I64 ! mut tcp udp)))
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
