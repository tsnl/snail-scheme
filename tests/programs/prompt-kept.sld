(import
 (snail core base)
 (snail core io))

;; What keeps a result keeps none of a call that suspended: a top-level
;; value's initializer runs again on the next read.
(define failing (→ (Prompt String Never)) (make-prompt))

(record Count
  ((value I64)))

(define attempts (→ Count) (new Count (value 0)))

;; How often the value below was computed.
(define (attempt!) (→ I64)
  (set! (● attempts value) (+ (● attempts value) 1))
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
  (unit))
