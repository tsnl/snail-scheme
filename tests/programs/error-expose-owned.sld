(import
 (snail core base))

(struct Work
  ((run (FnOnce Unit))))

(: make (-> Work))
(define (make)
  (Work (once (lambda () (unit)))))

(expose make "make")
