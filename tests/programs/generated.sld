;; Libraries a program generates: squares computed when the library is
;; built, a PNG's bytes embedded as a byte array literal, and the length of
;; a file the producer linked.
(import
 (snail core base)
 (snail core io)
 (sample table)
 (sample blob))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (define bytes (pixel))

  (write out (squares))
  (newline out)
  (display out (array-length bytes))
  (newline out)
  (display out
   (string-join (map (lambda (index) (show (u8->i32 (array-ref bytes index)))) (iota 8)) " "))
  (newline out)
  (display out (greeting-length))
  (newline out)
  (unit))
