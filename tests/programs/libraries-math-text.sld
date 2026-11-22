(import
 (snail core base)
 (snail core io)
 (snail shell math)
 (snail shell text))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (display out (round (* 1000.0 (sin (/ pi 2.0)))))
  (newline out)
  (write-line out (string-upcase "Hello λ"))
  (display out (char-unicode-alphabetic? #\λ))
  (newline out)
  (unit))
