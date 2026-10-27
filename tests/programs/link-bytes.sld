;; `link-bytes` names a file that ships beside the payload instead of in
;; it; the program holds a Resource and reads the bytes with
;; `read-resource`. A library links files beside its own source, and the
;; program beside its own.
(import
 (snail-core base)
 (snail-core io)
 (snail-core resource)
 (sample linked))

(: image Resource)
(define image (link-bytes "data/./pixel.png"))

(write-line (greeting-text))
(define bytes (read-resource image))
(display (vector-length bytes))
(newline)
(display (string-join (map (lambda (index) (show (u8->i32 (vector-ref bytes index)))) (iota 8)) " "))
(newline)
