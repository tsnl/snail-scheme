(import
 (snail core base)
 (snail core io))

;; A TypeId drops rows at every depth, so a list of yielding functions is
;; refused as a yielding function is.
(effect Gen
  ((ctl yield (Fn I64 → I64))))

(define (gen) (→ I64) (! Gen) (+ 1 (yield 1)))

(define boxed (→ Any) (Any (list gen)))

(define hidden
  (→ (List (Fn → I64)))
  (match (downcast (List (Fn → I64)) boxed) ((Some value) value) ((None) (panic "type mismatch"))))
