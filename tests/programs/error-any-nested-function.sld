(import
 (snail core base)
 (snail core io))

;; A TypeId drops rows at every depth, so a list of yielding functions is
;; refused as a yielding function is.
(effect Gen
  ((ctl yield (-> I64 I64))))

(: gen (-> I64 ! Gen))
(define (gen) (+ 1 (yield 1)))

(: boxed Any)
(define boxed (type-convert (list gen) Any))

(: hidden (List (-> I64)))
(define hidden (type-convert boxed (List (-> I64))))
