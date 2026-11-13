(import
 (snail core base)
 (snail core io))

;; A type variable may stand for a function that performs effects, and
;; specialization erases an ordinary effect before the backend sees it, so
;; a conversion must name its types where it is written.
(effect Log
  ((log (Fn String → Unit))))

(define (box (value A)) (→ Any) (∀ (A)) (type-convert value Any))

(define (noisy) (→ Unit) (! Log) (log "hi"))

(define main
  (lambda ()
    ((ann (type-convert (box noisy) (Fn → Unit)) (Fn → Unit)))
    (unit)))
