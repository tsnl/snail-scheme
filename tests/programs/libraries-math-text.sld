(import
 (snail-core base)
 (snail-core io)
 (snail-core math)
 (snail-core text))

(display (round (* 1000.0 (sin (/ pi 2.0)))))
(newline)
(write-line (string-upcase "Hello λ"))
(display (char-unicode-alphabetic? #\λ))
(newline)
