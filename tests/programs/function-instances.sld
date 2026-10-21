;; Instances for function types: heads of different arities do not
;; overlap, and an instance is chosen by the function's parameter and
;; result types whatever effects the function has.
(import
 (lofi base)
 (lofi io))

(typeclass (Describe T)
  (: describe (-> T String)))

(instance (Describe I64)
  (define (describe x) "I64"))

(instance (Describe Bool)
  (define (describe x) "Bool"))

(instance (Describe String)
  (define (describe x) "String"))

(instance (Describe Unit)
  (define (describe x) "Unit"))

(instance (Describe (-> R))
  (requires (Describe R))
  (define (describe f) (string-append "(-> " (describe (f)) ")")))

(instance (Describe (-> A R))
  (requires (Describe A) (Describe R))
  (define (describe f) "a unary function"))

(instance (Describe (-> A B R))
  (requires (Describe A) (Describe B) (Describe R))
  (define (describe f) "a binary function"))

(: positive? (-> I64 Bool))
(define (positive? n)
  (> n 0))

(write-line (describe (lambda () 7)))
(write-line (describe positive?))
(write-line (describe (lambda (a b) (+ a (ann b I64)))))
(write-line (describe write-line))
