(import
 (snail core base)
 (snail core io))

;; An instance method has its class method's row, even when this instance
;; performs less of it.
(typeclass (Announce T)
  (declare (announce (value T)) (→ Unit) (! Output-port)))

(instance (Announce I64)
  (define (announce (n I64)) (→ Unit) (! Output-port)
    (write-line (i64->string n))))

(instance (Announce Bool)
  (define (announce (b Bool)) (→ Unit) (! Output-port)
    (unit)))

;; A definition without a signature has no declared row to compare.
(define (next (n I64)) (→ I64)
  (+ n 1))

;; A quantified tail is performed by calling the function that carries it.
(define (twice (action (Fn → Unit ! E))) (→ Unit) (! E) (∀ (E))
  (action)
  (action))

(define (main) (→ Unit) (! Output-port)
  (announce 41)
  (announce #t)
  (twice (lambda () (announce (next 1))))
  (unit))
