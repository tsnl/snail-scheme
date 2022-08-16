(define a (p/invoke + 1 2))
(define b (p/invoke + 3 4))
(define c 
  (p/invoke + (p/invoke + a b) 1))

'(1 2 3 . 4)

'((1 2) . (3 4))
