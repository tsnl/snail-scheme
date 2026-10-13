(define-library (testing typeclasses)
  (export Render render <item> item item-value render-twice)
  (import (scheme base) (snail typing))
  (begin
    (define-record-type <item> (item value) item? (value : String item-value))
    (define-class (Render T) (: render (-> T String)))
    (define-instance (Render <item>) (render (lambda (value) (item-value value))))
    (: render-twice (All (A) (=> ((Render A)) (-> A String))))
    (define (render-twice value) (string-append (render value) (render value)))))
