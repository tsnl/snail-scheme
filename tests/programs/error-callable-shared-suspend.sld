(import
 (snail core base))

(effect Pause
  ((ctl pause (impl (Fn → Unit)))))

(struct Token
  ((number I64)))
(instance (Drop (!) Token)
  (define drop
    (lambda (token) (match token ((Token _) (unit))))))

(let* ((token (Token 10))
       (function (ann (lambda () (::number token) (pause))
                      (impl (Fn → Unit ! Pause)))))
  (drop function))
