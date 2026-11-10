(import
 (snail core base))

(: duplicate
   (All (F)
        (requires (Fn F I64 -> I64))
        (impl (Fn F -> (Pair F F)))))
(define (duplicate function)
  (Pair function function))
