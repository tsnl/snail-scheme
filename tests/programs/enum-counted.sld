(import
 (snail core base)
 (snail core io))

(effect Log ((record (Fn I64 → Unit))))

(struct Token
  ((value I64)))

(instance (Drop (! Log) Token)
  (define (drop (token Token)) (→ Unit) (! Log)
    (match token ((Token value) (record value)))))

(struct SharedCell
  ((owner (Rc Token))))

(enum Shared
  (Holding ((cell SharedCell)))
  (Empty))

(struct LinearCell
  ((token Token)))

(enum Linear
  (Owning ((cell LinearCell))))

(define (shared) (→ Unit) (! mut Log output-port)
  (let* ((value (Holding (SharedCell (rc (Token 1))))) (alias value))
    (match alias
      ((Holding cell) (set! (● cell owner) (rc (Token 2))))
      ((Empty) (panic "empty owner")))
    (match value
      ((Holding cell)
       (let ((previous (replace! (● cell owner) (rc (Token 3)))))
         (write-line (show (● previous value)))))
      ((Empty) (panic "empty owner")))))

(define (linear) (→ Unit) (! mut Log)
  (match (Owning (LinearCell (Token 4)))
    ((Owning cell)
     (drop (replace! (● cell token) (Token 5)))
     (drop cell))))

(define (main) (→ Unit) (! mut output-port)
  (handle Log ((record (lambda (value) (write-line (string-append "drop " (show value))))))
    (shared)
    (linear)))
