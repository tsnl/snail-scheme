(define-library (tests reject-payload)
  (export answer)
  (import (scheme base) (application reducer) (only (lofi core) ann -> I32))
  (begin
    (application counter (state I32 1) 0
                 (add (state (amount I32)) (no-effects (+ state amount))))
    (define answer (ann (lambda () (transition-state (dispatch counter 0 (add #t)))) (-> I32)))))
