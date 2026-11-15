(import
 (snail core base)
 (snail core io))

;; A function fits only where at least its effects are allowed.
(define (run (action (Fn → Unit))) (→ Unit)
  (action))

(define (noisy (action (Fn → Unit ! Output-port))) (→ Unit) (! Output-port)
  (action)
  (run action))

(define (main) (→ Unit) (! Output-port)
  (noisy (lambda () (write-line "noise"))))
