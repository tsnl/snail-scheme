(import
 (rename (lofi core)
         (data declare-data)
         (deriving derive)
         (def bind)
         (begin splice))
 (lofi base)
 (rename (only (macro deriving) derive-reader) (derive-reader renamed-reader)))

(bind private-increment (lambda (value) 0))
(bind def (lambda (value) 0))
(bind begin (lambda (value) 0))
(splice
 (declare-data Box ()
               (box (read-value I32 box-value))
               (derive renamed-reader)))
(read-value (box 41))
