(import
 (lofi base))

(struct Work
  ((run (Once (-> Unit)))))

(: make (-> Work))
(define (make)
  (Work (once (lambda () (unit)))))

(expose make "make")
