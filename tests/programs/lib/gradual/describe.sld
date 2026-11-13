(define-library (gradual describe)
  (export
   Describe describe)
  (import
   (snail core base))
  (begin
    (typeclass (Describe e T)
      (: describe (Fn T → String ! e)))

    (instance (Describe (!) I64)
      (define describe (lambda (value) (i64->string value))))

    (instance (Describe (!) String)
      (define describe (lambda (value) value)))

    (instance (Describe (!) (List I64))
      (define describe (lambda (value) (i64->string (length value)))))

    (instance (Describe (! dyn-cast) Any)
      (dispatch I64 String (List I64)))))
