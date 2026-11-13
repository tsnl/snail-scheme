(import
 (snail core base)
 (only (snail shell task) tasks Scheduler dispatch-in)
 (only (snail core forms) host)
 (rename (snail shell socket)
         (send udp-send)
         (receive udp-receive)))

;; A mismatch here is a broken test-host invariant.
(define-syntax fixture-convert
  (syntax-rules ()
    ((_ value target)
     (match (downcast target value)
       ((Some checked) checked)
       ((None) (panic "fixture payload has the wrong type"))))))

;; ---- Requests ----

;; Each operation that waits runs as a task, as a program's would:
;; `begin-NAME` dispatches one and answers its task's id, and once
;; `answered` holds for that id, `answer` is the operation's result, as an
;; Any, which the accessors below convert back. A task that traps never
;; answers; the host reports the trap under the same id.
(struct Slot
  ((value (Option Any))))

(struct Requests
  ((slots (List (Pair I64 Slot)))))

(define (requests) (→ Requests) (Requests (Nil)))
(expose requests "requests")

(define (request (scheduler Scheduler) (requests Requests) (work (FnOnce → Any ! tcp udp tasks)))
  (→ I64) (! mut host tcp udp)
  (let* ((slot (Slot (None)))
         (id (dispatch-in scheduler (once (lambda () (set! (● slot value) (Some (work))))))))
    (set! (● requests slots) (Cons (Pair id slot) (● requests slots)))
    id))

(define (slot (requests Requests) (id I64)) (→ Slot)
  (match (assoc-ref (● requests slots) id)
    ((Some found) found)
    ((None) (panic "no such request"))))

(define (answered? (requests Requests) (id I64)) (→ Bool)
  (match (● (slot requests id) value)
    ((Some _) #t)
    ((None) #f)))

(define (answer (requests Requests) (id I64)) (→ Any) (! mut)
  (match (replace! (● (slot requests id) value) (None))
    ((Some result)
     (set! (● requests slots) (filter (lambda (entry) (not (= (● entry first) id)))
                                      (● requests slots)))
     result)
    ((None) (panic "the request has not answered"))))

(define (truth (answer Any)) (→ I32)
  (if (fixture-convert answer Bool) 1 0))

(expose answered? "answered")
(expose answer "answer")
(expose truth "truth")

;; ---- Operations ----

(define (require (result (Result T SocketError))) (→ T) (∀ (T))
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
  (match (write (Connection (Any (ann 1 I32))) #u8(9 8 7))
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

(define (begin-open (scheduler Scheduler) (requests Requests)) (→ I64) (! mut host tcp udp)
  (request scheduler requests (once (lambda () (Any (open))))))

(define (begin-dial (scheduler Scheduler) (requests Requests) (port I32))
  (→ I64)
  (! mut host tcp udp)
  (request scheduler requests (once (lambda () (Any (dial port))))))

(define (begin-take (scheduler Scheduler) (requests Requests) (listener Listener))
  (→ I64)
  (! mut host tcp udp)
  (request scheduler requests (once (lambda () (Any (take listener))))))

(define (begin-receive (scheduler Scheduler)
                       (requests Requests)
                       (connection Connection)
                       (count I32))
  (→ I64)
  (! mut host tcp udp)
  (request scheduler requests (once (lambda () (Any (receive connection count))))))

(define (begin-send (scheduler Scheduler) (requests Requests) (connection Connection))
  (→ I64)
  (! mut host tcp udp)
  (request scheduler requests (once (lambda () (Any (send connection))))))

(define (begin-overwrite (scheduler Scheduler) (requests Requests)) (→ I64) (! mut host tcp udp)
  (request scheduler requests (once (lambda () (Any (overwrite))))))

(define (begin-finish (scheduler Scheduler) (requests Requests) (connection Connection) (grace I32))
  (→ I64)
  (! mut host tcp udp)
  (request scheduler requests (once (lambda () (Any (finish connection grace))))))

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

(define (begin-open-udp (scheduler Scheduler) (requests Requests)) (→ I64) (! mut host tcp udp)
  (request scheduler requests (once (lambda () (Any (open-udp))))))

(define (begin-send-udp (scheduler Scheduler) (requests Requests) (socket UdpSocket) (port I32))
  (→ I64)
  (! mut host tcp udp)
  (request scheduler requests (once (lambda () (Any (send-udp socket port))))))

(define (begin-receive-udp (scheduler Scheduler) (requests Requests) (socket UdpSocket) (count I32))
  (→ I64)
  (! mut host tcp udp)
  (request scheduler requests (once (lambda () (Any (receive-udp socket count))))))

(expose begin-open-udp "begin-open-udp")
(expose udp-socket "udp-socket")
(expose udp-port "udp-port")
(expose begin-send-udp "begin-send-udp")
(expose begin-receive-udp "begin-receive-udp")
(expose packet-port "packet-port")
(expose packet-size "packet-size")
(expose packet-byte "packet-byte")
(expose stop-udp "stop-udp")
