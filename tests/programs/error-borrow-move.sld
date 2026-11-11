(import
 (snail core base))

(: stolen (All (T) (impl (Fn (Borrow T) -> T))))
(define (stolen value)
  value)
