(import
 (snail core base)
 (snail core io))

(record Counter
  ((value I64)))

(define (consume (function (Fn I64 → I64 ! mut output-port)) (value I64))
  (→ I64)
  (! mut output-port)
  (function value))

(record Work
  ((run (Fn I64 → I64 ! mut output-port))))

(define (main) (→ Unit) (! mut output-port)

  (let* ((counter (new Counter (value 0)))
         (advance (ann (lambda (amount)
                         (set! (● counter value) (+ (● counter value) amount))
                         (● counter value))
                       (Fn I64 → I64 ! mut output-port))))
    (write-line (show (advance 3)))
    (write-line (show (advance 4)))
    (unit))
  ;; A procedure can keep another procedure.
  (let* ((counter (new Counter (value 0)))
         (inner (ann (lambda (amount)
                       (set! (● counter value) (+ (● counter value) amount))
                       (● counter value))
                     (Fn I64 → I64 ! mut output-port)))
         (outer (ann (lambda (amount) (inner amount))
                     (Fn I64 → I64 ! mut output-port))))
    (write-line (show (outer 2)))
    (unit))
  ;; A procedure passed on is the same procedure.
  (let* ((counter (new Counter (value 0)))
         (advance (ann (lambda (amount)
                         (set! (● counter value) amount)
                         (● counter value))
                       (Fn I64 → I64 ! mut output-port))))
    (write-line (show (consume advance 9))))
  ;; A procedure stored in a field remains callable through each alias.
  (let* ((counter (new Counter (value 0)))
         (work (new Work (run (lambda (amount)
                                (set! (● counter value) amount)
                                (● counter value))))))
    (write-line (show ((● work run) 12)))
    (unit))
  (unit))
