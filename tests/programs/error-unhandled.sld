(import
 (snail core base))

(effect Ask
  ((ask (Fn → I64))))

(define main
  (lambda ()
    (ask)
    (unit)))
