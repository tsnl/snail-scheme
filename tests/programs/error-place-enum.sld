(import
 (snail core base))

;; A field path cannot select a case without matching the enum first.
(enum Shape
  (Dot
   ((x I64)))
  (Empty))

(define (main) (→ Unit)
  (let ((cell (Dot 1)))
    (set! (● cell x) 2))
  (unit))
