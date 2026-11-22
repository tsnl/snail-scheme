(import
 (snail core base)
 (rename (snail core io) (write write-value))
 (snail shell task)
 (snail shell socket))

(define (require (result (Result T SocketError))) (→ T) (∀ (T))
  (match result
    ((Ok value) value)
    ((Err error) (panic (● error code)))))

(define (receive-four (tcp Tcp) (connection Connection)) (→ Bytes) (! mut)
  (let loop ((bytes #u8()))
    (if (= (array-length bytes) 4)
        bytes
        (match (require (read tcp connection (i64->i32 (- 4 (array-length bytes)))))
          ((Some chunk) (loop (array-append bytes chunk)))
          ((None) (panic "unexpected EOF"))))))

(define (main (tcp Tcp) (out OutputPort)) (→ Unit) (! mut)
  ;; A program waits on sockets from a task, which the scheduler runs once
  ;; main returns.
  (dispatch
   (lambda ()
     (let* ((listener (require (listen tcp (require (endpoint "127.0.0.1" 0)))))
            (client
             (require (connect tcp (require (endpoint "127.0.0.1" (● listener port))))))
            (server (require (accept tcp listener))))
       (require (close-listener tcp listener))
       (require (close-listener tcp listener))
       (display out (require (write tcp client #u8(0 255 128 1))))
       (newline out)
       (write-value out (array->list (receive-four tcp server)))
       (newline out)
       ;; A read takes 1 to 65,536 bytes, and a grace is not negative.
       (for-each (lambda (maximum)
                   (match (read tcp server maximum)
                     ((Err error) (write-line out (● error code)))
                     ((Ok _) (panic "a read out of bounds was started"))))
                 (list (ann 0 I32) (ann 65537 I32)))
       (match (finish-connection tcp server -1)
         ((Err error) (write-line out (● error code)))
         ((Ok _) (panic "a negative grace was accepted")))
       (require (close-connection tcp client))
       (require (close-connection tcp server))
       (require (close-connection tcp server))
       (match (read tcp server 1)
         ((Err error) (write-line out (● error code)))
         ((Ok _) (panic "closed socket was read"))))

     ;; Only `endpoint` makes an Endpoint: four decimal octets without
     ;; leading zeros, and a port from 0 to 65535.
     (for-each (lambda (address)
                 (match (endpoint address 80)
                   ((Err error) (write-line out (● error code)))
                   ((Ok _) (panic (string-append "accepted " address)))))
               (list "localhost"
                     "1.2.3"
                     "1.2.3.4.5"
                     "256.1.1.1"
                     "01.2.3.4"
                     "1..3.4"
                     ""
                     "1.2.3.4 "))
     (for-each (lambda (port)
                 (match (endpoint "127.0.0.1" port)
                   ((Err error) (write-line out (● error code)))
                   ((Ok _) (panic "a port out of range was accepted"))))
               (list -1 65536))
     (write-line out (Endpoint-address (require (endpoint "0.0.0.0" 65535))))
     (write-line out (Endpoint-address (require (endpoint "255.255.255.255" 0))))

     ;; A token from a replacement handler cannot masquerade as a native handle.
     (match (close-connection tcp (new Connection (token (Any (ann 1 I32)))))
       ((Err error) (write-line out (● error code)))
       ((Ok _) (panic "a fake token was accepted")))

     ;; Returning from main must close even a delivered listener left open by user code.
     (require (listen tcp (require (endpoint "127.0.0.1" 0))))

     (let* ((listener (require (listen tcp (require (endpoint "127.0.0.1" 0)))))
            (client
             (require (connect tcp (require (endpoint "127.0.0.1" (● listener port))))))
            (server (require (accept tcp listener))))
       (require (close-listener tcp listener))
       (dispatch (lambda () (require (finish-connection tcp server 1000))))
       (require (finish-connection tcp client 1000))
       (write-line out "finished"))))
  (unit))
