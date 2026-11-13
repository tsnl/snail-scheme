(import
 (snail core base)
 (snail core io))

(effect Stop ((ctl stop (Fn → I64))))
(struct Counter
  ((value I64)))
(define counter (→ Counter) (Counter 0))
(define first (→ I64)
  (unsafe-total (lambda () (set! (● counter value) 1) 10)))

(define (main) (→ Unit) (! output-port)
  ;; Cancellation must not skip the lazy read before the yielding operand.
  (write-line
   (show (handle Stop ((stop (lambda (resume) (drop resume) 99)))
           (+ first (stop)))))
  (write-line (show (● counter value))))
