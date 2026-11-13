(import
 (snail core base))

(effect Pause
  ((ctl pause (Fn → Unit))))

(struct Token
  ((number I64)))

(instance (Drop (!) Token)
  (define (drop (token Token)) (→ Unit)
    (match token ((Token _) (unit)))))

(define main
  (lambda ()
    (let* ((token (Token 10))
           (function (ann (lambda () (● token number) (pause))
                          (Fn → Unit ! Pause))))
      (drop function))
    (unit)))
