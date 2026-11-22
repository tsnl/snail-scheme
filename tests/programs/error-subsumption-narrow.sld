(import
 (snail core base)
 (snail core io))

;; A function fits only where at least its effects are allowed.
(define (run (action (Fn → Unit))) (→ Unit)
  (action))

(define (noisy (action (Fn → Unit ! mut))) (→ Unit) (! mut)
  (action)
  (run action))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (noisy (lambda () (write-line out "noise"))))
