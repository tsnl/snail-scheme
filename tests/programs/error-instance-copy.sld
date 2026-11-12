(import
 (snail core base)
 (snail core io))

;; An instance that requires (Copy A) may duplicate an A, so it is used
;; only where A is unrestricted: used at a FnOnce, it would run the work
;; twice.
(typeclass (Twice T)
  (: twice (Fn T → (Pair T T))))

(instance (Twice (Option A))
  (⊨ (Copy A))
  (define twice
    (lambda (value) (Pair value value))))

(define (run (option (Option (FnOnce → Unit ! output-port)))) (→ Unit) (! output-port)
  (match option
    ((Some work) (call-once work))
    ((None) (unit))))

(match (twice (Some (once (lambda () (write-line "ran")))))
  ((Pair x y) (run x) (run y)))
