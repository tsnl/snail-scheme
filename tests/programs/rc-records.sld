(import
 (snail core base)
 (snail core io))
(struct Resource
  ((value I64)))
(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource ((Resource value) (display value) (newline)))))
(struct Holder
  ((item (Rc Resource))))
(let ((holder (Holder (rc (Resource 1)))))
  (let ((alias holder))
    (set! (● alias item) (rc (Resource 2)))
    (display (● (● holder item) value))
    (newline))
  (display 3) (newline))
(display 4) (newline)
(let ((item (Some (rc (Resource 5))))) (display 6) (newline) (unit))
