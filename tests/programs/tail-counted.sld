(import
 (snail core base)
 (snail core io))

(effect Finalized ((record-finalizer (Fn → Unit))))
(struct Resource
  ((value I64)))
(struct Counter
  ((value I64)))
(instance (Drop (! Finalized) Resource)
  (define (drop (resource Resource)) (→ Unit) (! Finalized)
    (match resource ((Resource _) (record-finalizer)))))

;; Each iteration owns a shared argument and a fresh counted local. Both
;; must leave before the tail transfer, including through a type annotation.
(define (iterate (remaining I64) (shared (Rc Resource)))
  (→ I64) (! Finalized mut)
  (if (= remaining 0) (● shared value)
      (let ((temporary (rc (Resource remaining))))
        (ann (iterate (- remaining 1) shared) I64))))

(define (main) (→ Unit) (! mut output-port)
  (let ((counter (Counter 0)))
    (handle Finalized
        ((record-finalizer (lambda () (set! (● counter value) (+ (● counter value) 1)))))
      (write-line (show (iterate 200000 (rc (Resource 42))))))
    (write-line (show (● counter value))))
  (unit))
