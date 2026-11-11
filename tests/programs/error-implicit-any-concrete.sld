(import
 (snail core base))

(: integer (impl (Fn I64 -> I64)))
(define (integer value) value)
(integer "wrong")
