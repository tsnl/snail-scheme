(import
 (snail core base)
 (snail core io))

(struct Counter
  ((value I64)))

(instance (Drop (! mut output-port) Counter)
  (define drop
    (lambda (counter) (match counter
                        ((Counter value)
                         (write-line (string-append "released " (show value))))))))

(define (consume (function (FnOnce I64 → I64 ! mut output-port)) (value I64))
  (→ I64)
  (! mut output-port)
  (function value))

(struct Work
  ((run (Fn I64 → I64 ! mut output-port))))

(define main
  (lambda ()
    (let* ((counter (rc (Counter 0)))
           (advance (ann (lambda (amount)
                           (set! (● counter value) (+ (● counter value) amount))
                           (● counter value))
                         (Fn I64 → I64 ! mut output-port))))
      (write-line (show (advance 3)))
      (write-line (show (advance 4)))
      (drop advance))
    ;; A reusable procedure can keep another counted procedure.
    (let* ((counter (rc (Counter 0)))
           (inner (ann (lambda (amount)
                         (set! (● counter value) (+ (● counter value) amount))
                         (● counter value))
                       (Fn I64 → I64 ! mut output-port)))
           (outer (ann (lambda (amount) (inner amount))
                       (Fn I64 → I64 ! mut output-port))))
      (write-line (show (outer 2)))
      (drop outer))
    ;; Wrapping a counted procedure in once transfers one of its owners.
    (let* ((counter (rc (Counter 0)))
           (advance (ann (lambda (amount)
                           (set! (● counter value) amount)
                           (● counter value))
                         (Fn I64 → I64 ! mut output-port))))
      (write-line (show (consume (once advance) 9))))
    ;; A procedure stored in a field remains callable through each alias.
    (let* ((counter (rc (Counter 0)))
           (work (Work (lambda (amount)
                         (set! (● counter value) amount)
                         (● counter value)))))
      (write-line (show ((● work run) 12)))
      (drop work))
    (unit)))
