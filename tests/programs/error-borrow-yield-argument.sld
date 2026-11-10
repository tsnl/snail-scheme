(import
 (snail core base))

(effect Pause
  ((ctl pause (dyn (Fn -> Unit)))))

(struct Token
  ((number I64))
  (deriving Move))

(: inspect (impl (Fn (Borrow Token) Unit -> I64)))
(define (inspect token ignored)
  (::number token))

(let ((token (Token 1)))
  (handle Pause
      ((pause (lambda (resume) (resume (unit)))))
    (with-borrow (borrowed token)
                 (inspect borrowed (pause))))
  (drop token))
