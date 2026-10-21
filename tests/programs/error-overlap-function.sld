(import
 (lofi base))

(typeclass (Describe T)
  (: describe (-> T String)))

(instance (Describe (-> A R))
  (define (describe f) "any unary function"))

(instance (Describe (-> I64 R))
  (define (describe f) "a function of an I64"))
