(import
 (snail-core base)
 (snail-core io))

;; A control implementation that drops `resume` compiles; one that calls
;; it does not yet, since resuming the rest of the handled body is not
;; compiled.
(effect Gen
  ((ctl next (-> I64 Unit))))

(: collect (-> (List I64)))
(define (collect)
  (handle Gen ((next (lambda (value resume) (Cons value (resume (unit))))))
    (next 1)
    (next 2)
    (Nil)))

(for-each (lambda (value) (display value) (newline)) (collect))
