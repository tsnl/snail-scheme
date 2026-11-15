(import
 (snail core base))

(enum Choice
  (Chosen ((value I64)))
  (Empty))

(define main
  (lambda ()
    (● (Chosen 1) value)
    (unit)))
