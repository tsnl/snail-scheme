(import (snail strict))

(define state (ref 0))
(define (wide) (ref-set! state (+ (ref-get state) 1)) 7)
(define (narrow) (ref-set! state (+ (ref-get state) 1)) (ann 7 I32))
(define (flag) (ref-set! state (+ (ref-get state) 1)) #t)
(define (discard-wide) (when #t (wide)))
(define (discard-narrow) (unless #f (narrow)))
(define (discard-flag) (flag) (unit) (unit))

(ann (discard-wide) Unit)
(ann (discard-narrow) Unit)
(ann (discard-flag) Unit)
(ref-get state)
