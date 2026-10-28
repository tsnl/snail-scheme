(define-library (handler helper)
  (export answer)
  (import
   (snail core base))
  (begin
    ;; Linked code retains its selected Num evidence in the typed body.
    (: answer (-> I64))
    (define (answer) (+ 1 1))))
