(define-library (prim)
  (export once)
  (import
   (snail core base))
  (begin
    (define (once (work (Fn → Unit))) (→ (Fn → Unit)) work)))
