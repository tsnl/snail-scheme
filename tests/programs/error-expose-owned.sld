(import
 (snail core base))

(struct Work
  ((run (dyn (FnOnce → Unit)))))

(define (make) (→ Work)
  (Work (once (lambda () (unit)))))

(expose make "make")
