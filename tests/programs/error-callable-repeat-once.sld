(import
 (snail core base))

(: repeated
   (All (F)
        (requires (Copy F) (Fn F I64 -> I64))
        (impl (Fn F -> I64))))
(define (repeated function)
  (function (function 1)))

(repeated (once (lambda (value) (+ value 1))))
