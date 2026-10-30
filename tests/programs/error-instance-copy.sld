(import
 (snail core base)
 (snail core io))

;; An instance that requires (Copy A) may duplicate an A, so it is used
;; only where A is unrestricted: used at a FnOnce, it would run the work
;; twice.
(typeclass (Twice T)
  (: twice (-> T (Pair T T))))

(instance (Twice (Option A))
  (requires (Copy A))
  (define (twice value)
    (Pair value value)))

(: run (-> (Option (FnOnce Unit ! console)) Unit ! console))
(define (run option)
  (match option
    ((Some work) (call-once work))
    ((None) (unit))))

(match (twice (Some (once (lambda () (write-line "ran")))))
  ((Pair x y) (run x) (run y)))
