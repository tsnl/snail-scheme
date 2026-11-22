(import
 (snail core base))

;; Calling work closed over its handlers performs whatever its handlers
;; and the host do, which a total function may not.
(define (run (work (Fn → Unit ! mut))) (→ Unit)
  (work))
