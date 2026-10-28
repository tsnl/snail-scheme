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
    ((_ name) (define (name x) (* x x)))))

(define-square square)

;; A core keyword may be shadowed.
(: twice (-> (-> I64 I64) I64 I64))
(define (twice if x)
  (if (if x)))

(display (pairs (1 2 3) (4) 5))
(newline)
(write-line (pick else))
(write-line (let ((else 1)) (pick else)))
(define temporary 10)
(display (with-temporary 1 temporary))
(newline)
(display (square 7))
(newline)
(display (twice (lambda (n) (* n 3)) 2))
(newline)
