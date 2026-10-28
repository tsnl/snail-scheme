(define-library (prim)
  (export once)
  (import
   (snail core base))
  (begin
    (: once (-> (-> Unit) (-> Unit)))
    (define (once work) work)))
