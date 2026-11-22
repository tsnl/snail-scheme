(import
 (snail core base)
 (snail core io))

;; What keeps a result keeps none of a call that suspended: a top-level
;; value's initializer runs again on the next read, and a cache runs its
;; function again for the same key.
(define failing (→ (Prompt String Never)) (make-prompt))

(define asking (→ (Prompt I64 I64)) (make-prompt))

(record Count
  ((value I64)))

(define attempts (→ Count) (new Count (value 0)))

;; The counter is the test's own, so `attempt!` makes the `Mut` it counts
;; with.
(define (attempt!) (→ I64)
  (set! (unsafe-mut) (● attempts value) (+ (● attempts value) 1))
  (● attempts value))

;; A value that fails the first time it is read.
(define fragile
  (→ I64)
  (let ((attempt (attempt!)))
    (if (< attempt 2) (absurd (suspend failing "not yet")) (* attempt 21))))

(define (read-fragile (out OutputPort)) (→ Unit)
  (write-line out
              (with-prompt failing
                           (lambda () (show fragile))
                           (lambda (why resume) (string-append "failed: " why)))))

(define (main (out OutputPort)) (→ Unit)
  (read-fragile out)
  (read-fragile out)
  (read-fragile out)
  (write-line out (string-append "attempts: " (show (● attempts value))))
  ;; A call that suspended and was resumed has its value, and the cache
  ;; has none: the same key asks again.
  (let ((remembered (cache (lambda (n) (+ n (suspend asking n))))))
    (write-line out
                (show (with-prompt asking
                                   (lambda () (+ (remembered 1) (remembered 1)))
                                   (lambda (n resume)
                                     (write-line out (string-append "asked " (show n)))
                                     (resume (* n 10)))))))
  (unit))
