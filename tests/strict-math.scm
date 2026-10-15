(import (snail strict) (snail math))

;; ---- A scalar worker exercises all three shared Rust exports ----

(: trigonometry (-> I64 F64 F64))
(define (trigonometry operation value)
  (if (= operation 0) (sin value)
      (if (= operation 1) (cos value) (atan value))))

(unit)
