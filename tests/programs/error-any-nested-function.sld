(import
 (snail core base)
 (snail core io))

;; A TypeId drops rows at every depth, so a list of yielding functions is
;; refused as a yielding function is.
(effect Gen
  ((ctl yield (Fn I64 → I64))))

(define (gen) (→ I64) (! Gen) (+ 1 (yield 1)))

(define boxed (→ Any) (type-convert (list gen) Any))

(define hidden (→ (List (Fn → I64))) (type-convert boxed (List (Fn → I64))))
