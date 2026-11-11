(import
 (snail core base))
(: duplicate (All (T) (requires (Copy T)) (impl (Fn T -> (Pair T T)))))
(define (duplicate value) (Pair value value))
(duplicate (once (lambda () (unit))))
