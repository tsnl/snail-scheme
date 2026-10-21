(import
 (lofi base))

(: f (-> Bool I64))
(define (f x)
  (match x
    (_ 1)
    (#t 2)))
