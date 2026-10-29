(import
 (snail core base)
 (snail core io))

;; A declaration's grade follows its fields with its parameters bound, so
;; one that holds a linear value only in a Ref is unrestricted, through
;; recursion too: this chain of cells of work items is named twice. Each
;; item is swapped out of its cell, so the second walk finds them gone.
(type Work (FnOnce Unit ! console))

(enum (Chain T)
  (End)
  (Link ((cell (Ref T))
         (next (Chain T)))))

(: run-chain (-> (Chain (Option Work)) Unit ! console mut))
(define (run-chain chain)
  (match chain
    ((End) (unit))
    ((Link cell next)
     (match (ref-replace! cell (None))
       ((Some work) (call-once work))
       ((None) (write-line "gone")))
     (run-chain next))))

(let* ((chain (Link (ref (Some (once (lambda () (write-line "one")))))
                    (Link (ref (Some (once (lambda () (write-line "two"))))) (End))))
       (again chain))
  (run-chain chain)
  (run-chain again))
