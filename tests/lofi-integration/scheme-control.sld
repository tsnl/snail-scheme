(import
 (scheme base)
 (only (lofi primitive) ref ref-get ref-set!))
(define state (ref 0))
(define (touch value) (begin (ref-set! state (+ (ref-get state) 1)) value))
(when (and #t (or (touch #t) (touch #f))) (ref-set! state (+ (ref-get state) 40)))
(unless #t (ref-set! state 999))
(cond ((= (ref-get state) 41) (+ (ref-get state) 1)) (else 0))
