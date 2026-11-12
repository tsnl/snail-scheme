(import
 (snail core base)
 (snail core io))

;; An ordinary class may select a control row. Calling it preserves the
;; yield and resumes through the correct specialized method.
(effect Gen
  ((ctl next (Fn → Unit))))
(typeclass (Store e S)
  (: fetch-object (Fn S String → String ! e)))

(struct Loud
  ((name String)))

(instance (Store (! Gen) Loud)
  (define fetch-object
    (lambda (loud name) (next)
            name)))

(handle Gen
    ((next (lambda (resume)
             (write-line "yielded")
             (resume (unit)))))
  (write-line (fetch-object (Loud "loud") "answer")))
