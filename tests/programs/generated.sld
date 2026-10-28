;; Libraries a program generates: squares computed when the library is
;; built, and a PNG's bytes embedded as a byte vector literal.
(import
 (snail-core base)
 (snail-core io)
 (sample table)
 (sample blob))

(display squares)
(newline)
(display (vector-length pixel))
(newline)
(display
 (string-join (map (lambda (index) (show (u8->i32 (vector-ref pixel index))))
                   (iota 8))
              " "))
(newline)
