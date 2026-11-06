(import
 (snail core base))

(effect Pause
  ((ctl pause (-> Unit))))

(struct Token
  ((number I64))
  (deriving Move))

(: inspect (-> (Borrow Token) Unit I64))
(define (inspect token ignored)
  (Token-number token))

(let ((token (Token 1)))
  (handle Pause
      ((pause (lambda (resume) (resume (unit)))))
    (with-borrow (borrowed token)
                 (inspect borrowed (pause))))
  (drop token))
