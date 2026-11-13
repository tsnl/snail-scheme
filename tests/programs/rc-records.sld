(import
 (snail core base)
 (snail core io))

(record Resource
  ((value I64)))

(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource ((Resource value) (display value) (newline)))))

(record Holder
  ((item (Rc Resource))))

(define (main) (→ Unit) (! mut output-port)
  (let ((holder (new Holder (item (rc (new Resource (value 1)))))))
    (let ((alias holder))
      (set! (● alias item) (rc (new Resource (value 2))))
      (display (● (● holder item) value))
      (newline))
    (display 3) (newline))
  (display 4)
  (newline)
  (let ((item (Some (rc (new Resource (value 5)))))) (display 6) (newline) (unit))
  (unit))
