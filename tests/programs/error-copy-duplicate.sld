(import
 (snail core base))
(: duplicate (All (T) (impl (Fn T -> (Pair T T)))))
(define (duplicate value) (Pair value value))
(duplicate 1)
