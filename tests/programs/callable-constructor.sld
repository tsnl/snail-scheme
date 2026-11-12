(import
 (snail core base)
 (snail core io))

(struct Token
  ((label String)))

(instance (Drop (! output-port) Token)
  (define drop
    (lambda (token) (match token ((Token label) (write-line label))))))

(define main
  (lambda ()
    (let* ((token (Token "first-class cleanup"))
           (function (ann (lambda (value) (string-append (● token label) value))
                          (Fn String → String ! output-port)))
           (constructor once)
           (single (constructor function)))
      (write-line (single " called")))
    (let* ((token (Token "first-class abandoned"))
           (function (ann (lambda () (● token label)) (Fn → String ! output-port)))
           (constructor once)
           (single (constructor function)))
      (drop single))
    (let ((single (once (ann (fn (value) (+ value 1)) (fn I64 → I64)))))
      (write-line (show (single 4))))
    (unit)))
