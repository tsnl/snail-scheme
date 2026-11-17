;; A two-texel PNG, as bytes and as a data URL.
(import
 (snail core base)
 (snail core io)
 (snail shell png))

(define png (→ Bytes) (rgba->png 2 1 (list->array (map i32->u8 (list 255 0 0 255 0 255 0 128)))))

(write-line (string-join (map (lambda (byte) (show (u8->i32 byte))) (array->list png)) " "))
(write-line (png-data-url png))
