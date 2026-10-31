(define-library (gradual describe)
  (export
   Describe describe)
  (import
   (snail core base))
  (begin
    (typeclass (Describe T)
      (: describe (-> T String)))

    (instance (Describe I64)
      (define (describe value) (i64->string value)))

    (instance (Describe String)
      (define (describe value) value))

    (instance (Describe (List I64))
      (define (describe value) (i64->string (length value))))

    (instance (Describe Any)
      (dispatch I64 String (List I64)))))
