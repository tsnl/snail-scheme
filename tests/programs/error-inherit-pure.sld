(import
 (snail core base)
 (only (snail core forms) Host))

;; Calling work closed over its handlers performs whatever its handlers
;; and the host do, which a total function may not.
(define (run (work (Fn → Unit ! Host))) (→ Unit)
  (work))
