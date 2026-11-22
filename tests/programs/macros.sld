(import
 (snail core base)
 (snail core io))

;; Nested ellipses with trailing elements.
(define-syntax pairs
  (syntax-rules ()
    ((_ (key value ...) ... last) (list (list key value ...) ... (list last)))))

;; Literals match by binding: a local `else` is not the keyword.
(define-syntax pick
  (syntax-rules (else)
    ((_ else) "keyword")
    ((_ other) "expression")))

;; A template binder does not capture the caller's variable.
(define-syntax with-temporary
  (syntax-rules ()
    ((_ value body) (let ((temporary value)) body))))

;; A macro that defines a function the caller names.
(define-syntax define-square
  (syntax-rules ()
    ((_ name) (define (name (x I64)) (→ I64) (* x x)))))

(define-square square)

;; A core keyword may be shadowed.
(define (twice (if (Fn I64 → I64)) (x I64)) (→ I64)
  (if (if x)))

(define (temporary) (→ I64) 10)

(define (main (out OutputPort)) (→ Unit)
  (write out (pairs (1 2 3) (4) 5))
  (newline out)
  (write-line out (pick else))
  (write-line out (let ((else 1)) (pick else)))
  (display out (with-temporary 1 (temporary)))
  (newline out)
  (display out (square 7))
  (newline out)
  (display out (twice (lambda (n) (* n 3)) 2))
  (newline out)
  (unit))
