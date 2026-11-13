(import
 (snail core base)
 (snail core io))

(struct Record
  ((value I64)))

(typeclass (Describe T)
  (: describe (Fn T → I64)))

(define-instance-set fields
  (instance (Describe Record)
    (define (describe (record Record)) (→ I64)
      (+ (● record value) 1))))

;; Instance scopes do not participate in field selection.
(define reader (with-instances (fields) (lambda (record) (● record value))))

(define (main) (→ Unit) (! output-port)
  (display (reader (Record 17)))
  (newline)
  (unit))
