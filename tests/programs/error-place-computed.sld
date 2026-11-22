(import
 (snail core base))

(record Circle
  ((radius I64)))

(define (main) (→ Unit)
  ;; No stored x slot exists to write.
  (let ((cell (new Circle (radius 1))))
    (set! (● cell x) 4))
  (unit))
