(define-library (tests immutable)
  (export answer)
  (import (scheme base) (scheme immutable) (only (lofi core) ann -> I32))
  (begin
    (define-immutable-record Pair make-pair
      (left I32 left with-left) (right I32 right with-right))
    (define answer (ann (lambda ()
                          (let* ((prior (make-pair 10 20)) (next (with-right (with-left prior 42) 7)))
                            (if (and (= (left prior) 10) (= (right prior) 20) (= (left next) 42) (= (right next) 7)) 1 0)))
                        (-> I32)))))
