(import
 (snail core base)
 (snail core io))
(struct Token
  ((label String)))
(instance (Drop (! console) Token)
  (define (drop token)
    (match token ((Token label) (write-line label)))))

(let* ((token (Token "first-class cleanup"))
       (function (ann (lambda (value) (string-append (::label token) value))
                      (impl (Fn String -> String ! console))))
       (constructor once)
       (single (constructor function)))
  (write-line (single " called")))

(let* ((token (Token "first-class abandoned"))
       (function (ann (lambda () (::label token)) (impl (Fn -> String ! console))))
       (constructor once)
       (single (constructor function)))
  (drop single))

(let ((single (once (ann (fn (value) (+ value 1)) (fn I64 -> I64)))))
  (write-line (show (single 4))))
