(define-library (tests reject-owner)
  (export answer)
  (import (scheme base) (application reducer) (only (lofi core) ann -> I32))
  (begin
    (application first (state I32 1) 0
                 (add (state (amount I32)) (no-effects (+ state amount))))
    (application second (state I32 1) 0
                 (subtract (state (amount I32)) (no-effects (- state amount))))
    (define answer (ann (lambda () (transition-state (dispatch second 0 (add 1)))) (-> I32)))))
