(define-library (tests immutable)
  (export answer)
  (import
   (scheme base)
   (scheme immutable)
   (only (lofi core) ann -> I32))
  (begin
    (define-immutable-record Pair make-pair
      (left I32 left left-set)
      (right I32 right right-set))
    (define answer (ann (lambda ()
                          (let* ((prior (make-pair 10 20)) (next (right-set (left-set prior 42) 7)))
                            (if (and (= (left prior) 10) (= (right prior) 20) (= (left next) 42) (= (right next) 7)) 1 0)))
                        (-> I32)))))
