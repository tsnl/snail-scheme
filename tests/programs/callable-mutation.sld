(import
 (snail core base)
 (snail core io))

(struct Counter
  ((value (Ref I64))))

(instance (Drop (! mut output-port) Counter)
  (define drop
    (lambda (counter) (match counter
                        ((Counter value)
                         (write-line (string-append "released " (show (ref-get value)))))))))

(define (consume (function (FnOnce I64 → I64 ! mut output-port)) (value I64))
  (→ I64)
  (! mut output-port)
  (function value))

(struct Work
  ((run (Fn I64 → I64 ! mut output-port))))

(define main
  (lambda ()
    (let* ((counter (Counter (ref 0)))
           (advance (ann (lambda (amount)
                           (set! (ref-get (● counter value)) (+ (ref-get (● counter value)) amount))
                           (ref-get (● counter value)))
                         (Fn I64 → I64 ! mut output-port))))
      (write-line (show (advance 3)))
      (write-line (show (advance 4)))
      (drop advance))
    ;; An exclusive callable can reborrow its owned exclusive callback.
    (let* ((counter (Counter (ref 0)))
           (inner (ann (lambda (amount)
                         (set! (ref-get (● counter value)) (+ (ref-get (● counter value)) amount))
                         (ref-get (● counter value)))
                       (Fn I64 → I64 ! mut output-port)))
           (outer (ann (lambda (amount) (inner amount))
                       (Fn I64 → I64 ! mut output-port))))
      (write-line (show (outer 2)))
      (drop outer))
    ;; Consuming an exclusive implementation runs its capture cleanup once.
    (let* ((counter (Counter (ref 0)))
           (advance (ann (lambda (amount)
                           (set! (ref-get (● counter value)) amount)
                           (ref-get (● counter value)))
                         (Fn I64 → I64 ! mut output-port))))
      (write-line (show (consume advance 9))))
    ;; An erased exclusive receiver can be called through its owner's field.
    (let* ((counter (Counter (ref 0)))
           (work (Work (lambda (amount)
                         (set! (ref-get (● counter value)) amount)
                         (ref-get (● counter value))))))
      (write-line (show ((● work run) 12)))
      (drop work))
    (unit)))
