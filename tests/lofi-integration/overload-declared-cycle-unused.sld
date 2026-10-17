(import
 (lofi base))
(define-overload f (-> I64 I64) (lambda (value) (helper value)))
(def helper
     (lambda (value) (f value)))
42
