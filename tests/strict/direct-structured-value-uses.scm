(import (snail strict))

(define saved (ref (ann (lambda () 0) (-> I64))))
(define answer
  ((let ()
     (define (value) 42)
     (ref-set! saved value)
     value)))
(define (choose flag)
  ((let ()
     (define (yes) answer)
     (define (no) 0)
     (if flag yes no))))

(if (and (= ((ref-get saved)) 42) (= (choose #t) 42) (= (choose #f) 0)) 42 0)
