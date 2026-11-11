(define-library (prim)
  (export once)
  (import
   (snail core base))
  (begin
    (define (once (work (dyn (Fn → Unit)))) (→ (dyn (Fn → Unit))) work)))
