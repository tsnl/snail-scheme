(import
 (snail core base)
 (snail core io))

;; A declaration's grade follows its fields with its parameters bound,
;; through recursion too: this chain of cells is unrestricted and named
;; twice. Each content is swapped out of its cell, so the second walk
;; finds them gone.
(enum (Chain T)
  (End)
  (Link ((cell (Ref T))
         (next (Chain T)))))

(: run-chain (-> (Chain (Option String)) Unit ! console mut))
(define (run-chain chain)
  (match chain
    ((End) (unit))
    ((Link cell next)
     (match (ref-replace! cell (None))
       ((Some text) (write-line text))
       ((None) (write-line "gone")))
     (run-chain next))))

(let* ((chain (Link (ref (Some "one")) (Link (ref (Some "two")) (End))))
       (again chain))
  (run-chain chain)
  (run-chain again))
