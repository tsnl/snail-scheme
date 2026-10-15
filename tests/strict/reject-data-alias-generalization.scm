(import (snail strict))
(define calls (ref 0))
(define-data (Box T) (box (value T unbox)))
(: make (All (T) (-> T (Box T))))
(define make
  (begin (ref-set! calls (+ (ref-get calls) 1)) box))
(unbox (make 42))
