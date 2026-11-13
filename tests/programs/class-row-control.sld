(import
 (snail core base)
 (snail core io))

;; An ordinary class may select a control row. Calling it preserves the
;; yield and resumes through the correct specialized method.
(effect Gen
  ((ctl next (Fn → Unit))))

(typeclass (Store e S)
  (declare (fetch-object (left S) (right String)) (→ String) (! e)))

(struct Loud
  ((name String)))

(instance (Store (! Gen) Loud)
  (define (fetch-object (loud Loud) (name String)) (→ String) (! Gen)
    (next)
    name))

(define (main) (→ Unit) (! output-port)

  (handle Gen
      ((next (lambda (resume)
               (write-line "yielded")
               (resume (unit)))))
    (write-line (fetch-object (Loud "loud") "answer")))
  (unit))
