(import
 (snail core base)
 (snail core io))

(define (use-wrapper (wrap (Fn (Fn String → Unit ! Output-port)
                               → (Fn String → Unit ! Output-port))))
  (→ Unit) (! Output-port)
  ((wrap write-line) "effect"))
(define (main) (→ Unit) (! Output-port) (use-wrapper cache))
