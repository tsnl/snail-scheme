(import
 (snail core base)
 (snail core io))

(record Resource
  ((value I64)))

(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource ((Resource value) (display value) (newline)))))

(define (copies (count I64) (resource (Rc Resource)) (items (List (Rc Resource))))
  (→ (List (Rc Resource)))
  (! mut output-port)
  (if (= count 0) items (copies (- count 1) resource (Cons resource items))))

(define (chain (count I64) (next (Fn → Unit ! mut output-port)))
  (→ (Fn → Unit ! mut output-port))
  (if (= count 0) next (chain (- count 1) (lambda () (next)))))

(define (leaf) (→ (Fn → Unit ! mut output-port))
  (let ((resource (rc (new Resource (value 2)))))
    (lambda () (display (● resource value)))))

(define (main) (→ Unit) (! mut output-port)
  (let ((resource (rc (new Resource (value 1)))))
    (drop (copies 100000 resource (Nil)))
    (unit))
  (drop (chain 100000 (leaf)))
  (display 3)
  (newline)
  (unit))
