(import
 (snail core base))

;; Cloning a value of a type variable needs the row of its copy.
(: twin (All (A) (impl (Fn A -> (Pair A A)))))
(define (twin value)
  (clone value))
