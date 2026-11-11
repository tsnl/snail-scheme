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
(define slots (→ (Ref (List (Pair I64 (Ref (Option Any)))))) (ref (Nil)))

(define (request (work (dyn (FnOnce → Any ! tcp udp tasks)))) (→ I64) (! mut tcp udp)
  (let* ((slot (ref (ann (None) (Option Any))))
         (id (dispatch-task (once (lambda () (ref-set! slot (Some (work))))))))
    (ref-set! slots (Cons (Pair id slot) (ref-get slots)))
    id))

(define (slot (id I64)) (→ (Ref (Option Any))) (! mut)
  (match (assoc-ref (ref-get slots) id)
    ((Some found) found)
    ((None) (panic "no such request"))))

(define (answered? (id I64)) (→ Bool) (! mut)
  (match (ref-get (slot id))
    ((Some _) #t)
    ((None) #f)))

(define (answer (id I64)) (→ Any) (! mut)
  (match (ref-get (slot id))
    ((Some result) result)
    ((None) (panic "the request has not answered"))))

(define (truth (answer Any)) (→ I32)
  (if (fixture-convert answer Bool) 1 0))

(expose answered? "answered")
(expose answer "answer")
(expose truth "truth")

;; ---- Operations ----

(define (require (result (Result T SocketError))) (→ T) (∀ T)
  (match result
    ((Ok value) value)
    ((Err error) (panic (● error code)))))

(define (open) (→ (Result Listener SocketError)) (! tcp tasks)
  (listen (require (endpoint "127.0.0.1" 0))))

(define (listener (answer Any)) (→ Listener)
  (require (fixture-convert answer (Result Listener SocketError))))

(define (port (listener Listener)) (→ I32) (● listener port))

(define (dial (port I32)) (→ (Result Connection SocketError)) (! tcp tasks)
  (connect (require (endpoint "127.0.0.1" port))))

(define (take (listener Listener))
  (→ (Result Connection SocketError))
  (! tcp tasks)
  (accept listener))

(define (connection (answer Any)) (→ Connection)
  (require (fixture-convert answer (Result Connection SocketError))))

(define (receive (connection Connection) (count I32))
  (→ (Result (Option Bytes) SocketError))
  (! tcp tasks)
  (read connection count))

(define (read-count (answer Any)) (→ I32)
  (match (require (fixture-convert answer (Result (Option Bytes) SocketError)))
    ((Some bytes) (i64->i32 (vector-length bytes)))
    ((None) -1)))

(define (read-byte (answer Any) (index I32)) (→ I32)
  (match (require (fixture-convert answer (Result (Option Bytes) SocketError)))
    ((Some bytes) (u8->i32 (vector-ref bytes (i32->i64 index))))
    ((None) -1)))

(define (bad-read? (answer Any)) (→ Bool)
  (match (fixture-convert answer (Result (Option Bytes) SocketError))
    ((Err error) (string=? (● error code) "EBADF"))
    ((Ok _) #f)))

(define (send (connection Connection))
  (→ (Result I32 SocketError))
  (! tcp tasks)
  (write connection #u8(0 255 128 1)))

(define (written (answer Any)) (→ I32)
  (require (fixture-convert answer (Result I32 SocketError))))

(define (overwrite) (→ Bool) (! tcp tasks)
  (match (write (Connection (type-convert (ann 1 I32) Any)) #u8(9 8 7))
    ((Err error) (string=? (● error code) "EBADF"))
    ((Ok _) #f)))

(define (stop-listener (listener Listener)) (→ Unit) (! tcp) (require (close-listener listener)))

(define (stop-connection (connection Connection))
  (→ Unit)
  (! tcp)
  (require (close-connection connection)))

(define (finish (connection Connection) (grace I32))
  (→ (Result Unit SocketError))
  (! tcp tasks)
  (finish-connection connection grace))

(define (finished? (answer Any)) (→ Bool)
  (match (fixture-convert answer (Result Unit SocketError))
    ((Ok _) #t)
    ((Err _) #f)))

(define (timed-out? (answer Any)) (→ Bool)
  (match (fixture-convert answer (Result Unit SocketError))
    ((Err error) (string=? (● error code) "ETIMEDOUT"))
    ((Ok _) #f)))

(define (begin-open) (→ I64) (! mut tcp udp)
  (request (once (lambda () (type-convert (open) Any)))))

(define (begin-dial (port I32)) (→ I64) (! mut tcp udp)
  (request (once (lambda () (type-convert (dial port) Any)))))

(define (begin-take (listener Listener)) (→ I64) (! mut tcp udp)
  (request (once (lambda () (type-convert (take listener) Any)))))

(define (begin-receive (connection Connection) (count I32)) (→ I64) (! mut tcp udp)
  (request (once (lambda () (type-convert (receive connection count) Any)))))

(define (begin-send (connection Connection)) (→ I64) (! mut tcp udp)
  (request (once (lambda () (type-convert (send connection) Any)))))

(define (begin-overwrite) (→ I64) (! mut tcp udp)
  (request (once (lambda () (type-convert (overwrite) Any)))))

(define (begin-finish (connection Connection) (grace I32)) (→ I64) (! mut tcp udp)
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

(define (open-udp) (→ UdpSocket) (! udp tasks) (require (bind (require (endpoint "127.0.0.1" 0)))))

(define (udp-socket (answer Any)) (→ UdpSocket)
  (fixture-convert answer UdpSocket))

(define (udp-port (socket UdpSocket)) (→ I32) (● socket port))

(define (send-udp (socket UdpSocket) (port I32)) (→ (Result I32 SocketError)) (! udp tasks)
  (udp-send socket (require (endpoint "127.0.0.1" port)) #u8(0 255 128 1)))

(define (receive-udp (socket UdpSocket) (count I32))
  (→ (Result Datagram SocketError))
  (! udp tasks)
  (udp-receive socket count))

(define (datagram (answer Any)) (→ Datagram)
  (require (fixture-convert answer (Result Datagram SocketError))))

(define (packet-port (answer Any)) (→ I32) (Endpoint-port (● (datagram answer) peer)))

(define (packet-size (answer Any)) (→ I32) (i64->i32 (vector-length (● (datagram answer) bytes))))

(define (packet-byte (answer Any) (index I32)) (→ I32)
  (u8->i32 (vector-ref (● (datagram answer) bytes) (i32->i64 index))))

(define (stop-udp (socket UdpSocket)) (→ Unit) (! udp) (require (close-udp socket)))

(define (begin-open-udp) (→ I64) (! mut tcp udp)
  (request (once (lambda () (type-convert (open-udp) Any)))))

(define (begin-send-udp (socket UdpSocket) (port I32)) (→ I64) (! mut tcp udp)
  (request (once (lambda () (type-convert (send-udp socket port) Any)))))

(define (begin-receive-udp (socket UdpSocket) (count I32)) (→ I64) (! mut tcp udp)
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
