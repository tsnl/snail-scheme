(import
 (snail core base)
 (snail core io))

;; An instance method has its class method's row, even when this instance
;; performs less of it.
(typeclass (Announce T)
  (declare (announce (out OutputPort) (value T)) (→ Unit) (! mut)))

(instance (Announce I64)
  (define (announce (out OutputPort) (n I64)) (→ Unit) (! mut)
    (write-line out (i64->string n))))

(instance (Announce Bool)
  (define (announce (out OutputPort) (b Bool)) (→ Unit) (! mut)
    (unit)))

;; A definition without a signature has no declared row to compare.
(define (next (n I64)) (→ I64)
  (+ n 1))

;; A quantified tail is performed by calling the function that carries it.
(define (twice (action (Fn → Unit ! e))) (→ Unit) (! e) (∀ (e))
  (action)
  (action))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (announce out 41)
  (announce out #t)
  (twice (lambda () (announce out (next 1))))
  (unit))
