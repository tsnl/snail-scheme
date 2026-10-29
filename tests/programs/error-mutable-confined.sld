(import
 (snail core base))

;; Writing a parameter's mutable field mutates storage from outside, which
;; a function whose type forbids mut may not do.
(struct Counter
  ((count mut I64)))

(: reset (-> Counter Unit))
(define (reset counter)
  (Counter-count-set! counter 0))

(reset (Counter 3))
