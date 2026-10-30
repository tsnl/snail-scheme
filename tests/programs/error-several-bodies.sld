(import
 (snail core base)
 (snail core io))

;; Each body that fails is reported, and the bodies after it are still
;; expanded: one compile names both unbound identifiers, in order.
(: twice (-> I64 I64))
(define (twice n)
  (+ n missing))

(: fine (-> I64 I64))
(define (fine n)
  (* n 2))

(write-line (show (fine (also-missing 1))))
