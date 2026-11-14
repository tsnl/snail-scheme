(import
 (snail core base)
 (snail core io))

;; An instance that requires (Copy A) may duplicate an A, so it is used
;; only where A is unrestricted: used at a FnOnce, it would run the work
;; twice.
(typeclass (Twice T)
  (declare (twice (value T)) (→ (Pair T T))))

(instance (Twice (Option A))
  (⊨ (Copy A))
  (define (twice (value (Option A))) (→ (Pair (Option A) (Option A)))
    (new Pair (first value) (second value))))

(define (run (option (Option (FnOnce → Unit ! output-port)))) (→ Unit) (! output-port)
  (match option
    ((Some work) (call-once work))
    ((None) (unit))))

(define main
  (lambda ()
    (match (twice (Some (once (lambda () (write-line "ran")))))
      ((Pair x y) (run x) (run y)))
    (unit)))
