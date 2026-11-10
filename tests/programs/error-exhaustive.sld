(import
 (snail core base))

(: f (impl (Fn (Option I64) -> I64)))
(define (f x)
  (match x
    ((Some n) n)))
