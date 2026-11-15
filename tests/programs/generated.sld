;; Libraries a program generates: squares computed when the library is
;; built, a PNG's bytes embedded as a byte array literal, and the length of
;; a file the producer linked.
(import
 (snail core base)
 (snail core io)
 (sample table)
 (sample blob))

(define (main) (→ Unit) (! output-port)
  (define bytes (pixel))

  (write (squares))
  (newline)
  (display (array-length bytes))
  (newline)
  (display
   (string-join (map (lambda (index) (show (u8->i32 (array-ref bytes index)))) (iota 8)) " "))
  (newline)
  (display (greeting-length))
  (newline)
  (unit))
