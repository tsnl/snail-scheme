;; `read-resources` reads several linked files together: it starts every
;; read, waits once for all of them, and answers the bytes in the order
;; asked. The same file asked for twice is one read on the host, under
;; two tickets, which complete together.
(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell resource))

(define (text) (→ Resource) (link-file "linked-resource.txt"))

(define (image) (→ Resource) (link-file "data/pixel.png"))

(define (main) (→ Unit) (! output-port resource tasks)
  (for-each (lambda (bytes)
              (write-line (string-append (show (array-length bytes))
                                         " bytes, starting "
                                         (show (u8->i32 (array-ref bytes 0))))))
            (read-resources (list (text) (text) (image))))
  (unit))
