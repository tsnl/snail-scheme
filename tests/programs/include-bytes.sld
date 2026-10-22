;; `include-bytes` spells a byte vector literal holding a file's bytes; the
;; path is relative to this file.
(import
 (lofi base)
 (lofi io))

(define image (include-bytes "data/pixel.png"))
(display (vector-length image))
(newline)
(display (string-join (map (lambda (index) (show (u8->i32 (vector-ref image index)))) (iota 8)) " "))
(newline)
