(import
 (snail core base)
 (snail core io))

;; A TypeId drops rows at every depth, so a list of yielding functions is
;; refused as a yielding function is.
(effect Gen
  ((ctl yield (dyn (Fn I64 -> I64)))))

(: gen (impl (Fn -> I64 ! Gen)))
(define (gen) (+ 1 (yield 1)))

(: boxed Any)
(define boxed (type-convert (list gen) Any))

(: hidden (List (dyn (Fn -> I64))))
(define hidden (type-convert boxed (List (dyn (Fn -> I64)))))
