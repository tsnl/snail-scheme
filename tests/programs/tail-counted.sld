(import
 (snail core base)
 (snail core io))

(effect Finalized ((record-finalizer (Fn → Unit))))
(record Resource
  ((value I64)))
(record Counter
  ((value I64)))
(instance (Drop (! Finalized) Resource)
  (define (drop (resource Resource)) (→ Unit) (! Finalized)
    (match resource ((Resource _) (record-finalizer)))))

;; Each iteration owns a shared argument and a fresh counted local. Both
;; must leave before the tail transfer, including through a type annotation.
(define (iterate (remaining I64) (shared (Rc Resource)))
  (→ I64) (! Finalized mut)
  (if (= remaining 0) (● shared value)
      (let ((temporary (rc (new Resource (value remaining)))))
        (ann (iterate (- remaining 1) shared) I64))))

(define (main) (→ Unit) (! mut output-port)
  (let ((counter (new Counter (value 0))))
    (handle Finalized
        ((record-finalizer (lambda () (set! (● counter value) (+ (● counter value) 1)))))
      (write-line (show (iterate 200000 (rc (new Resource (value 42)))))))
    (write-line (show (● counter value))))
  (unit))
