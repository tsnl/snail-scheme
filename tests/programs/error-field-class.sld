(import
 (snail core base))
(record Record
  ((value I64)))
;; Labels no longer introduce classes, including in instance position.
(instance (::value Record I64)
  (define (read-value (record Record)) (→ I64) (● record value)))
