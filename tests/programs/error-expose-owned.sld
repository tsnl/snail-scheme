(import
 (snail core base))

(struct Work
  ((run (FnOnce → Unit))))

(define (make) (→ Work)
  (Work (once (lambda () (unit)))))

(expose make "make")
