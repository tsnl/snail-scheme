(import
 (snail core base)
 (snail core io))

(record Counter
  ((value I64)))

(define (consume (out OutputPort) (function (Fn I64 → I64)) (value I64))
  (→ I64)
  (function value))

(record Work
  ((run (Fn I64 → I64))))

(define (main (out OutputPort)) (→ Unit)

  (let* ((counter (new Counter (value 0)))
         (advance (ann (lambda (amount)
                         (set! (● counter value) (+ (● counter value) amount))
                         (● counter value))
                       (Fn I64 → I64))))
    (write-line out (show (advance 3)))
    (write-line out (show (advance 4)))
    (unit))
  ;; A procedure can keep another procedure.
  (let* ((counter (new Counter (value 0)))
         (inner (ann (lambda (amount)
                       (set! (● counter value) (+ (● counter value) amount))
                       (● counter value))
                     (Fn I64 → I64)))
         (outer (ann (lambda (amount) (inner amount))
                     (Fn I64 → I64))))
    (write-line out (show (outer 2)))
    (unit))
  ;; A procedure passed on is the same procedure.
  (let* ((counter (new Counter (value 0)))
         (advance (ann (lambda (amount)
                         (set! (● counter value) amount)
                         (● counter value))
                       (Fn I64 → I64))))
    (write-line out (show (consume out advance 9))))
  ;; A procedure stored in a field remains callable through each alias.
  (let* ((counter (new Counter (value 0)))
         (work (new Work (run (lambda (amount)
                                (set! (● counter value) amount)
                                (● counter value))))))
    (write-line out (show ((● work run) 12)))
    (unit))
  (unit))
