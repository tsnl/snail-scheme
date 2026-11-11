(import
 (snail core base))

(instance (Show (!) (List I64))
  (define show (lambda (items) "numbers")))
