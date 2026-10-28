(import
 (snail core base)
 (snail core io))

;; A type variable may stand for a function that performs effects, and
;; specialization erases an ordinary effect before the backend sees it, so
;; a conversion must name its types where it is written.
(effect Log
  ((log (-> String Unit))))

(: box (All (A) (-> A Any)))
(define (box value) (type-convert value Any))

(: noisy (-> Unit ! Log))
(define (noisy) (log "hi"))

((ann (type-convert (box noisy) (-> Unit)) (-> Unit)))
