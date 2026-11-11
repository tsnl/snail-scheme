(import
 (snail core base))

(: f (impl (Fn Bool -> I64)))
(define (f x)
  (match x
    (_ 1)
    (#t 2)))
