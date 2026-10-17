(define-library (tests counter-lofi)
  (export answer)
  (import (lofi core) (lofi base) (application reducer))
  (begin
    (application counter (state I32 1) 0
                 (add (state (amount I32)) (no-effects (i32-add state amount))))
    (def answer (-> I32)
         (lambda () (transition-state (dispatch counter 40 (add 2)))))))
