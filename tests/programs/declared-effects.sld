(import
 (snail core base)
 (snail core io))

;; An instance method has its class method's row, even when this instance
;; performs less of it.
(typeclass (Announce T)
  (: announce (Fn T → Unit ! output-port)))

(instance (Announce I64)
  (define announce (lambda (n) (write-line (i64->string n)))))

(instance (Announce Bool)
  (define announce (lambda (b) (unit))))

;; A definition without a signature has no declared row to compare.
(define next (lambda (n) (+ n 1)))

;; A quantified tail is performed by calling the function that carries it.
(define (twice (action (Fn → Unit ! e))) (→ Unit) (! e) (∀ e)
  (action)
  (action))

(define (main) (→ Unit) (! output-port)
  (announce 41)
  (announce #t)
  (twice (lambda () (announce (next 1))))
  (unit))
