(import
 (snail core base)
 (snail core io))

(struct Counter
  ((value I64)))
(define trace (→ Counter) (Counter 0))
(define (record (n I64)) (→ Unit) (! mut)
  (set! (● trace value) (+ (* 10 (● trace value)) n)))

(struct Token
  ((value I64)))
(instance (Drop (! mut) Token)
  (define (drop (token Token)) (→ Unit) (! mut)
    (match token ((Token value) (record value)))))

(define procedure (→ (Fn I64 → I64 ! mut))
  (unsafe-total
   (lambda ()
     (record 1)
     (lambda (value) (record 4) value))))

(define (invoke) (→ I64) (! mut)
  (let ((owner (rc (Token 3))))
    ;; The getter runs before the argument and the outgoing owner's release.
    (procedure (begin (record 2) (● owner value)))))

(define (main) (→ Unit) (! mut output-port)
  (invoke)
  (write-line (show (● trace value)))
  (invoke)
  (write-line (show (● trace value))))
