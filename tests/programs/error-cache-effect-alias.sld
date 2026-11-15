(import
 (snail core base)
 (snail core io))

(define (main) (→ Unit) (! Output-port)
  (let* ((wrap cache) (memo (wrap write-line))) (memo "effect")))
