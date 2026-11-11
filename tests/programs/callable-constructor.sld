(import
 (snail core base)
 (snail core io))
(struct Token
  ((label String)))
(instance (Drop (! console) Token)
  (define drop
    (lambda (token) (match token ((Token label) (write-line label))))))

(let* ((token (Token "first-class cleanup"))
       (function (ann (lambda (value) (string-append (● token label) value))
                      (impl (Fn String → String ! console))))
       (constructor once)
       (single (constructor function)))
  (write-line (single " called")))

(let* ((token (Token "first-class abandoned"))
       (function (ann (lambda () (● token label)) (impl (Fn → String ! console))))
       (constructor once)
       (single (constructor function)))
  (drop single))

(let ((single (once (ann (fn (value) (+ value 1)) (fn I64 → I64)))))
  (write-line (show (single 4))))
