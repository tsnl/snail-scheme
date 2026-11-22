;; Reads a binary file, a PNG whose bytes are not text, as bytes.
(import
 (snail core base)
 (snail core io))

(define (main (fs Fs) (out OutputPort)) (→ Unit)

  (define image (read-bytes fs "tests/programs/data/pixel.png"))
  (display out (array-length image))
  (newline out)
  (display out
           (string-join (map (lambda (index) (show (u8->i32 (array-ref image index)))) (iota 8))
                        " "))
  (newline out)
  (unit))
