(import
 (snail core base))
(define (integer (value Any)) (→ I64) (type-convert value I64))
