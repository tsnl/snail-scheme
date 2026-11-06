(import
 (snail core base)
 (snail core io))
(struct Record
  ((value I64)))
(define-instance-set fields
  (instance (::other Record I64)
    (define (::other record) (::value record))))
(define reader (with-instances (fields) ::other))
(display (reader (Record 17)))
(newline)
