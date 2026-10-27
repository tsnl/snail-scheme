(import
 (snail-core base)
 (snail-core io))

;; A control operation type-checks, with `resume` handed to its
;; implementation; the backend does not compile it yet.
(effect Gen
  ((ctl next (-> I64 Unit))))

(: collect (-> (List I64)))
(define (collect)
  (handle Gen ((next (lambda (value resume) (Cons value (resume (unit))))))
    (next 1)
    (next 2)
    (Nil)))

(for-each (lambda (value) (display value) (newline)) (collect))
