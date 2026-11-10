(define-library (prim)
  (export once)
  (import
   (snail core base))
  (begin
    (: once (impl (Fn (dyn (Fn -> Unit)) -> (dyn (Fn -> Unit)))))
    (define (once work) work)))
