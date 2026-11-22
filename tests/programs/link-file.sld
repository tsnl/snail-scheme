;; `link-file` ties a file to the library that names it: the build ships
;; the file beside the payload instead of in it, and the program holds a
;; Resource. A task reads the bytes with `read-resource`, which waits until
;; the host has read the file. A library links files beside its own
;; source, and the program beside its own.
(import
 (only (snail core forms) host)
 (snail core base)
 (snail core io)
 (only (snail shell task) tasks dispatch)
 (snail shell resource)
 (sample linked))

(define (image) (→ Resource) (link-file "data/./pixel.png"))

(define (main (resources Resources) (out OutputPort)) (→ Unit) (! host mut tasks)
  (dispatch
   (lambda ()
     (write-line out (greeting-text resources))
     (let ((bytes (read-resource resources (image))))
       (display out (array-length bytes))
       (newline out)
       (display out
        (string-join
         (map (lambda (index) (show (u8->i32 (array-ref bytes index)))) (iota 8))
         " "))
       (newline out))))
  (unit))
