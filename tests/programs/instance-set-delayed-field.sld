(import
 (snail core base)
 (snail core io))
(struct Record
  ((value I64)))
(typeclass (Describe T)
  (: describe (impl (Fn T → I64))))
(define-instance-set fields
  (instance (Describe Record)
    (define (describe (record Record)) (→ I64)
      (+ (● record value) 1))))
;; Instance scopes do not participate in field selection.
(define reader (with-instances (fields) (lambda (record) (● record value))))
(display (reader (Record 17)))
(newline)
