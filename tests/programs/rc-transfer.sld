(import
 (snail core base)
 (snail core io))

(record Resource
  ((value I64)))

(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource ((Resource value) (display value) (newline)))))

(record Holder
  ((value (Rc Resource))))

(define (identity (resource (Rc Resource))) (→ (Rc Resource)) resource)

(define (wrap (resource (Rc Resource))) (→ Holder) (new Holder (value resource)))

(define (duplicate (resource (Rc Resource))) (→ (Pair (Rc Resource) (Rc Resource)))
  (new Pair (first resource) (second resource)))

(define (reader (resource (Rc Resource))) (→ (Fn → I64 ! mut output-port))
  (lambda () (● resource value)))

(define (main) (→ Unit) (! mut output-port)
  (let ((resource (identity (rc (new Resource (value 8))))))
    (let ((holder (wrap resource))
          (both (duplicate resource))
          (read (reader resource)))
      (display (● (● holder value) value)) (newline)
      (display (● (● both first) value)) (newline)
      (display (read)) (newline)
      (unit))
    (display 9) (newline) (unit))
  (display 10)
  (newline)
  (unit))
