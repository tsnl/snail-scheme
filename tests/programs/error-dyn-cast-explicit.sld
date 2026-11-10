(import
 (snail core base))
(: integer (impl (Fn Any -> I64)))
(define (integer value) (type-convert value I64))
