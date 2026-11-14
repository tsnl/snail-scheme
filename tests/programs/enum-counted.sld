(import
 (snail core base)
 (snail core io))

(effect Log ((note (Fn I64 → Unit))))

(record Token
  ((value I64)))

(instance (Drop (! Log) Token)
  (define (drop (token Token)) (→ Unit) (! Log)
    (match token ((Token value) (note value)))))

(record SharedCell
  ((owner (Rc Token))))

(enum Shared
  (Holding ((cell SharedCell)))
  (Empty))

(record LinearCell
  ((token Token)))

(enum Linear
  (Owning ((cell LinearCell))))

(define (shared) (→ Unit) (! mut Log output-port)
  (let* ((value (Holding (new SharedCell (owner (rc (new Token (value 1))))))) (alias value))
    (match alias
      ((Holding cell) (set! (● cell owner) (rc (new Token (value 2)))))
      ((Empty) (panic "empty owner")))
    (match value
      ((Holding cell)
       (let ((previous (replace! (● cell owner) (rc (new Token (value 3))))))
         (write-line (show (● previous value)))))
      ((Empty) (panic "empty owner")))))

(define (linear) (→ Unit) (! mut Log)
  (match (Owning (new LinearCell (token (new Token (value 4)))))
    ((Owning cell)
     (drop (replace! (● cell token) (new Token (value 5))))
     (drop cell))))

(define (main) (→ Unit) (! mut output-port)
  (handle Log ((note (lambda (value) (write-line (string-append "drop " (show value))))))
    (shared)
    (linear)))
