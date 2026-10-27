(import
 (snail-core base))

;; vector-generate calls its callback from a loop in WAT, which cannot
;; leave early when the callback yields.
(effect Abort
  ((ctl abort (-> I64 I64))))

(: squares (-> I64 (Vector I64)))
(define (squares count)
  (handle Abort ((abort (lambda (value resume) (vector-generate 0 (lambda (index) index)))))
    (vector-generate count (lambda (index) (if (< index 3) (* index index) (abort index))))))

(squares 4)
