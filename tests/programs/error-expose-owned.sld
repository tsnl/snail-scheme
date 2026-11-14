(import
 (snail core base))

(record Work
  ((run (FnOnce → Unit))))

(define (make) (→ Work)
  (new Work (run (once (lambda () (unit))))))

(expose make "make")
