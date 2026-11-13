(import
 (only (snail core forms) host)
 (snail core base)
 (snail core io)
 (snail shell future))

(record Counter
  ((value I64)))

(define (main) (→ Unit) (! host mut output-port)
  (let ((wakes (new Counter (value 0))) (notifications (new Counter (value 0))))
    (handle completion
        ((completed (lambda () (set! (● notifications value) (+ 1 (● notifications value))))))
      (match (ann (make-promise) (Pair (Promise I64) (Future I64)))
        ((Pair promise future)
         (let* ((future (on-ready future (once (lambda () (set! (● wakes value) 100)))))
                (future
                 (on-ready future (once (lambda () (set! (● wakes value) (+ 1 (● wakes value))))))))
           (write-line (show (● wakes value)))
           (drop (fulfill promise 42))
           (write-line (show (● wakes value)))
           (let ((future
                  (on-ready future
                            (once (lambda () (set! (● wakes value) (+ 1 (● wakes value))))))))
             (write-line (show (● wakes value)))
             (match (poll future)
               ((Ready (Completed result)) (write-line (show result)))
               ((Ready (Abandoned)) (panic "unexpected abandonment"))
               ((Pending future) (drop future)))))))
      (match (ann (make-promise) (Pair (Promise I64) (Future I64)))
        ((Pair promise future)
         (let ((future
                (on-ready future (once (lambda () (set! (● wakes value) (+ 1 (● wakes value))))))))
           (drop promise)
           (drop future))))
      (write-line (show (● wakes value)))
      (write-line (show (● notifications value)))))
  (unit))
