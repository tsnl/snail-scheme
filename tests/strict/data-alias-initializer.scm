(import (snail strict))
(define calls (ref 0))
(define-data (Box T) (box (value T unbox)))
(define make
  (begin (ref-set! calls (+ (ref-get calls) 1)) box))
(define first (make 40))
(define second (make (+ (unbox first) 2)))
(if (= (ref-get calls) 1) (unbox second) (unreachable))
