(import
 (lofi primitive))
(def identity (All (T) (-> T T)) (lambda (T) (ann T T)))
(def Box (datatype (T)
           (box
            (value T))))
(def get (All (T) (-> (Box T) T)) (lambda (value) (match value ((box T) (ann T T)))))
(define-syntax use (syntax-rules () ((_ x) (get (box (identity x))))))
(use 42)
