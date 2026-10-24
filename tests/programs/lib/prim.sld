(define-library (prim)
  (export once)
  (import
   (lofi base))
  (begin
    (: once (-> (-> Unit) (-> Unit)))
    (define (once work) work)))
