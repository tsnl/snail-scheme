;; Reads a binary file, a PNG whose bytes are not text, as bytes.
(import
 (snail-core base)
 (snail-core io))

(define image (read-bytes "tests/programs/data/pixel.png"))
(display (vector-length image))
(newline)
(display (string-join (map (lambda (index) (show (u8->i32 (vector-ref image index)))) (iota 8)) " "))
(newline)
