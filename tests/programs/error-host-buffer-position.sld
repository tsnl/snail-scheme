(import
 (snail core base))

;; The host reads one String or Bytes argument, staged just before the call,
;; so a host function may take one only last.
(extern greet "snail.test" "greet" (-> String I64 Unit))
(greet "hello" 1)
