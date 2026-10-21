(import
 (lofi base)
 (lofi io))

;; A call that is not in tail position can recurse a million deep.
(: count-down (-> I64 (List I64)))
(define (count-down n)
  (if (= n 0) (Nil) (Cons n (count-down (- n 1)))))

(display (length (count-down 1000000)))
(newline)
