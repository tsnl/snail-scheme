(import
 (snail core base)
 (snail core io))

(struct Callback
  ((run (Fn I64 → I64))))
(define (identity (value I64)) (→ I64)
  value)
(define (duplicate (function (Fn I64 → I64))) (→ (Pair (Fn I64 → I64) (Fn I64 → I64)))
  (Pair function function))
(define (invoke (function (Fn → Unit ! e))) (→ Unit) (! e) (∀ (e))
  (function))

(define (main) (→ Unit) (! output-port)
  (let* ((function (● (Callback identity) run)) (both (duplicate function)))
    (write-line (show ((● both first) ((● both second) 42)))))
  (invoke (lambda () (write-line "ordinary procedures")))
  (unit))
