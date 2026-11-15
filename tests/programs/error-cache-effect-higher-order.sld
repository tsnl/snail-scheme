(import
 (snail core base)
 (snail core io))

(define (use-wrapper (wrap (Fn (Fn String → Unit ! output-port)
                               → (Fn String → Unit ! output-port))))
  (→ Unit) (! output-port)
  ((wrap write-line) "effect"))
(define (main) (→ Unit) (! output-port) (use-wrapper cache))
