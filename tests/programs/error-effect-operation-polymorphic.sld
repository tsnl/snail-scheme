(import
 (snail-core base)
 (snail-core io))

;; A handler implements an operation once, so the operation has one type.
;; Were it polymorphic, its implementation would be checked at whatever
;; type its first use chose, while each caller chose its own.
(effect Pick
  ((pick (All (A) (-> A A A)))))

(: choose (-> String ! console))
(define (choose)
  (handle Pick ((pick (lambda (a b) b)))
    (write-line (string-append (pick "x" "y") (show (pick 1 2))))
    "done"))

(write-line (choose))
