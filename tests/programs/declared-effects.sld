(import
 (snail core base)
 (snail core io))

;; An instance method has its class method's row, even when this instance
;; performs less of it.
(typeclass (Announce T)
  (: announce (-> T Unit ! console)))

(instance (Announce I64)
  (define (announce n) (write-line (i64->string n))))

(instance (Announce Bool)
  (define (announce b) (unit)))

;; A definition without a signature has no declared row to compare.
(define (next n) (+ n 1))

;; A quantified tail is performed by calling the function that carries it.
(: twice (All (e) (-> (-> Unit ! e) Unit ! e)))
(define (twice action)
  (action)
  (action))

(announce 41)
(announce #t)
(twice (lambda () (announce (next 1))))
