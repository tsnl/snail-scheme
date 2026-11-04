(import
 (snail core base))
(: integer (-> Any I64))
(define (integer value) (type-convert value I64))
