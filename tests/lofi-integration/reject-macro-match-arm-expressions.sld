(import
 (lofi core))

(data Box ()
  (box
   (value I32 box-value)))
(define-syntax invalid-match
     (syntax-rules ()
       ((_ subject) (match subject ((box value) value 42)))))
(invalid-match (box 0))
