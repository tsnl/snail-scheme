(define-library (gradual describe)
  (export
   Describe describe)
  (import
   (snail core base))
  (begin
    (typeclass (Describe e T)
      (: describe (-> T String ! e)))

    (instance (Describe (!) I64)
      (define (describe value) (i64->string value)))

    (instance (Describe (!) String)
      (define (describe value) value))

    (instance (Describe (!) (List I64))
      (define (describe value) (i64->string (length value))))

    (instance (Describe (! dyn-cast) Any)
      (dispatch I64 String (List I64)))))
