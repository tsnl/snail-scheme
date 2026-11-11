(import
 (snail core base))

(struct Work
  ((run (dyn (FnOnce -> Unit)))))

(: make (impl (Fn -> Work)))
(define (make)
  (Work (once (lambda () (unit)))))

(expose make "make")
