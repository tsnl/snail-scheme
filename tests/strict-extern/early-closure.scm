(import (snail strict))

(define-extern mark "probe" "mark" (-> I32 Unit))
(define base (ann 40 I32))
(: worker (-> I32 I32))
(define (worker value) (+ base value))
(define (invoke callback) (callback))
(define pending
  ((lambda ()
     (define read-later
       (lambda ()
         (mark (ann 3 I32))
         (+ base later)))
     (invoke read-later))))
(define later (ann 2 I32))
pending
