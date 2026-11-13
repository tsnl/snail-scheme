(import
 (snail core base)
 (snail core io))

(struct Token
  ((label String)))

(instance (Drop (! output-port) Token)
  (define drop
    (lambda (token) (match token ((Token label) (write-line label))))))

(define (append-resource (label String)) (→ (Fn String → String ! mut output-port))
  (let ((token (rc (Token label))))
    (lambda (value) (string-append (● token label) value))))

(define (read-resource (label String)) (→ (Fn → String ! mut output-port))
  (let ((token (rc (Token label))))
    (lambda () (● token label))))

(define (main) (→ Unit) (! mut output-port)
  (let* ((constructor once)
         (single (constructor (append-resource "first-class cleanup"))))
    (write-line (single " called")))
  (let* ((constructor once)
         (single (constructor (read-resource "first-class abandoned"))))
    (drop single))
  (let ((single (once (lambda (value) ((ann (lambda (n) (+ n 1)) (Fn I64 → I64)) value)))))
    (write-line (show (single 4))))
  (unit))
