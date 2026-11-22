(import
 (snail core base)
 (rename (snail core io) (write write-value))
 (snail shell task)
 (snail shell socket))

;; A mismatch here is a broken test-host invariant.
(define-syntax fixture-convert
  (syntax-rules ()
    ((_ value target)
     (match (downcast target value)
       ((Some checked) checked)
       ((None) (panic "fixture payload has the wrong type"))))))

(define (require (result (Result T SocketError))) (→ T) (∀ (T))
  (match result
    ((Ok value) value)
    ((Err error) (panic (● error code)))))

(record Buffer
  ((bytes Bytes)))

(define (main (out OutputPort)) (→ Unit)

  ;; A program waits on sockets from a task, which the scheduler runs once
  ;; main returns.
  ;; Mutable test state travels in operation arguments, not the reusable
  ;; handler's captures. A dispatched task inherits this handler across waits.
  (dispatch
   (lambda ()
     (let ((tcp (new Tcp
                  (listen
                   (lambda (endpoint)
                     (Ok (new Listener (token (Any endpoint)) (port (Endpoint-port endpoint))))))
                  (connect
                   (lambda (_) (Ok (new Connection (token (Any (new Buffer (bytes #u8()))))))))
                  (accept
                   (lambda (_) (Ok (new Connection (token (Any (new Buffer (bytes #u8()))))))))
                  (read (lambda (connection _)
                          (Ok
                           (Some
                            (● (fixture-convert (● connection token) Buffer) bytes)))))
                  (write (lambda (connection bytes)
                           (sleep 1)
                           (set! (● (fixture-convert (● connection token) Buffer) bytes) bytes)
                           (Ok (i64->i32 (array-length bytes)))))
                  (close-listener (lambda (_) (Ok (unit))))
                  (finish-connection (lambda (connection grace)
                                       (sleep 1)
                                       (display out grace)
                                       (newline out)
                                       (set!
                                        (● (fixture-convert (● connection token) Buffer) bytes)
                                        #u8())
                                       (Ok (unit))))
                  (close-connection (lambda (_) (Ok (unit)))))))
       (let ((connection (require (tcp::connect (require (endpoint "192.0.2.1" 0))))))
         (dispatch
          (lambda ()
            (require (tcp::write connection #u8(7 8)))
            (match (require (tcp::read connection 2))
              ((Some bytes) (write-value out (array->list bytes)))
              ((None) (panic "unexpected EOF")))
            (newline out)
            (require (tcp::finish-connection connection 250))))))))
  (write-line out "main returns")
  (unit))
