(import
 (snail-core base)
 (snail-core io))

(let ((greet (once (lambda () (write-line "called once")))))
  (greet)
  (greet))
