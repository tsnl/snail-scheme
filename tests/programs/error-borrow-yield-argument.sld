(import
 (snail core base))

(effect Pause
  ((ctl pause (dyn (Fn → Unit)))))

(struct Token
  ((number I64))
  (deriving Move))

(define (inspect (token (Borrow Token)) (ignored Unit)) (→ I64)
  (● token number))

(let ((token (Token 1)))
  (handle Pause
      ((pause (lambda (resume) (resume (unit)))))
    (with-borrow (borrowed token)
                 (inspect borrowed (pause))))
  (drop token))
