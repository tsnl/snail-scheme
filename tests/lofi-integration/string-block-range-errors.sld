(import (lofi base))

;; ---- Complete range rejection before the first block write ----

(def target
     (make-string (ann 16385 I64) #\λ))
(def source
     (make-string (ann 16385 I64) #\x1f600))

(def partial-source (-> Unit)
     (lambda () (string-copy! target (ann 0 I64) source (ann 8191 I64) (ann 16386 I64))))

(def partial-target (-> Unit)
     (lambda () (string-copy! target (ann 8191 I64) source (ann 0 I64) (ann 8195 I64))))

(def negative-start (-> Unit)
     (lambda () (string-copy! target (ann 0 I64) source (ann -1 I64) (ann 8192 I64))))

(def negative-end (-> Unit)
     (lambda () (string-copy! target (ann 0 I64) source (ann 0 I64) (ann -1 I64))))

(def wrapped-target (-> Unit)
     (lambda () (string-copy! target (ann 4294967295 I64) source (ann 0 I64) (ann 0 I64))))

(def wrapped-start (-> Unit)
     (lambda () (string-copy! target (ann 0 I64) source (ann 4294967295 I64) (ann 4294967295 I64))))

(def empty-past-target (-> Unit)
     (lambda () (string-copy! target (ann 16386 I64) source (ann 16385 I64) (ann 16385 I64))))

(def empty-past-source (-> Unit)
     (lambda () (string-copy! target (ann 16385 I64) source (ann 16386 I64) (ann 16386 I64))))

(def endpoint-index (-> Unit)
     (lambda () (string-set! target (ann 16385 I64) #\Z)))

(def unchanged (-> Bool)
     (lambda () (string=? target (make-string (ann 16385 I64) #\λ))))
(ann 42 I64)
