(define-library (macro literal-decisions)
  (export check-then-bind)
  (import
   (lofi core))
  (begin
    (def check-then-bind
         (syntax-rules (marker)
           ((_ marker 1) 0)
           ((_ name value) (def name value))))))
