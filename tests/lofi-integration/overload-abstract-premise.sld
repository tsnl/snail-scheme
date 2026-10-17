(import
 (lofi base))
(define-overload convert (-> I64 I64) (lambda (value) value))

(def abstract (All (A) (=> ((convert (-> A Bool))) (-> A Bool)))
     (lambda (value) (convert value)))
(ann 42 I64)
