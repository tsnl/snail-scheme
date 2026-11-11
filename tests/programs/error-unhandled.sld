(import
 (snail core base))

(effect Ask
  ((ask (dyn (Fn -> I64)))))

(ask)
