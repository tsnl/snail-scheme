(import
 (rename (lofi core)
         (data declare-data)
         (datatype legacy-datatype)
         (typeclass declare-class)
         (instance declare-instance)
         (begin splice)
         (def bind))
 (lofi base))

;; Lowered declaration heads must not capture these ordinary values.
(bind def (lambda (value) 0))
(bind datatype (lambda (value) 0))
(bind typeclass (lambda (value) 0))
(bind instance (lambda (value) 0))
(splice
 (declare-data Box ()
               (box (value I32 unbox)))
 (declare-class Identity (T)
                (: identity (-> T T)))
 (declare-instance identity-i32 (Identity I32)
                   (identity (lambda (value) value))))
(identity (unbox (box 42)))
