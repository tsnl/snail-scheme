(import
 (snail core base)
 (snail core io))

(effect Log ((record (Fn I64 → Unit))))

(struct Token
  ((value I64)))

(instance (Drop (! Log) Token)
  (define (drop (token Token)) (→ Unit) (! Log)
    (match token ((Token value) (record value)))))

(enum Shared
  (Holding ((owner (Rc Token))))
  (Empty))

(enum Linear
  (Owning ((token Token))))

(define (shared) (→ Unit) (! mut Log output-port)
  (let* ((value (Holding (rc (Token 1)))) (alias value))
    (Holding-owner-set! alias (rc (Token 2)))
    (let ((previous (Holding-owner-replace! value (rc (Token 3)))))
      (write-line (show (● previous value))))))

(define (linear) (→ Unit) (! mut Log)
  (let ((value (Owning (Token 4))))
    (drop (Owning-token-replace! value (Token 5)))
    (drop value)))

(define (main) (→ Unit) (! mut output-port)
  (handle Log ((record (lambda (value) (write-line (string-append "drop " (show value))))))
    (shared)
    (linear)))
