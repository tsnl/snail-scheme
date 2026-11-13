(import
 (snail core base))

;; vector-generate calls its callback from a loop in WAT, which cannot
;; leave early when the callback yields.
(effect Abort
  ((ctl abort (Fn I64 → I64))))

(define (squares (count I64)) (→ (Vector I64))
  (handle Abort ((abort
                  (lambda (value resume) (drop resume) (vector-generate 0 (lambda (index) index)))))
    (vector-generate count (lambda (index) (if (< index 3) (* index index) (abort index))))))

(define (main) (→ Unit)

  (squares 4)
  (unit))
