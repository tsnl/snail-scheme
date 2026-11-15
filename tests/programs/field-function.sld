(import
 (snail core base)
 (snail core io))

;; Former generated field names can be ordinary user functions.
(record Point
  ((x I64)))

(define (point-x (point Point)) (→ I64)
  (● point x))

(define (main) (→ Unit) (! Output-port)

  (write-line (show (point-x (new Point (x 1)))))
  (unit))
