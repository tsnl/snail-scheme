(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell resource))

(define (asset) (→ Resource) (link-file "linked-resource.txt"))

(define (main (resources Resources) (out OutputPort)) (→ Unit) (! mut tasks)
  (write-line out "before")
  (let ((bytes (read-resource resources (asset))))
    (display out (array-length bytes)) (newline out)
    (display out (u8->i32 (array-ref bytes 0))) (newline out))
  (sleep 1)
  (write-line out "after")
  (unit))
