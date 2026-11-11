(import
 (snail core base))

;; Ownership is checked an item at a time, so each item that misuses a
;; linear value is reported, though the first stops its own item.
(: duplicate (All (T) (impl (Fn T -> (Pair T T)))))
(define (duplicate value)
  (Pair value value))

(: fine (impl (Fn I64 -> I64)))
(define (fine n)
  (+ n 1))

(: forget (All (T) (impl (Fn T -> Unit))))
(define (forget value)
  (unit))

(duplicate (fine 1))
