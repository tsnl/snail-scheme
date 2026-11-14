(define-library (prim)
  (export work)
  (import
   (snail core base))
  (begin
    (define (work (Fn → Unit)) (→ (Fn → Unit)) work)))
