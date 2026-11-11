(define-library (handler helper)
  (export answer)
  (import
   (snail core base))
  (begin
    ;; Linked code retains its selected Num evidence in the typed body.
    (define (answer) (→ I64) (+ 1 1))))
