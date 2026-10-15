(define-library (testing polymorphism)
  (export identity text-id)
  (import (scheme base) (snail typing))
  (begin
    (: identity (All (A) (-> A A)))
    (define (identity x) x)
    (: text-id (-> String String))
    (define text-id (inst identity String))))
