(import
 (snail core base)
 (snail core io))

;; Each body that fails is reported, and the bodies after it are still
;; expanded: one compile names both unbound identifiers, in order.
(define (twice (n I64)) (→ I64)
  (+ n missing))

(define (fine (n I64)) (→ I64)
  (* n 2))

(write-line (show (fine (also-missing 1))))
