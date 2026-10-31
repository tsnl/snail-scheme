;; `link-file` ties a file to the library that names it: the build ships
;; the file beside the payload instead of in it, and the program holds a
;; Resource. A task reads the bytes with `read-resource`, which waits until
;; the host has read the file. A library links files beside its own
;; source, and the program beside its own.
(import
 (snail core base)
 (snail core io)
 (only (snail shell task) tasks dispatch-local)
 (snail shell resource)
 (sample linked))

(: image Resource)
(define image (link-file "data/./pixel.png"))

(dispatch-local
 (once (lambda ()
         (write-line (greeting-text))
         (let ((bytes (read-resource image)))
           (display (vector-length bytes))
           (newline)
           (display
            (string-join (map (lambda (index) (show (u8->i32 (vector-ref bytes index)))) (iota 8))
                         " "))
           (newline)))))
