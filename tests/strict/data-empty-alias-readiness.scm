(import (snail strict))
(define-data Empty (empty))
(define calls (ref 0))
(: observed (-> I64))
(define (observed) (ref-get calls))
(: invoke (-> I64))
(define (invoke)
  ;; Evaluating a nullary call's operator can have effects and fail readiness.
  (define first ((begin (ref-set! calls 1) alias)))
  (define alias empty)
  (match first ((empty) 42)))
42
