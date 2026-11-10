(import
 (snail core base))

;; unsafe-total discards its thunk's row, so nothing after it would test
;; for a yield.
(effect Abort
  ((ctl abort (dyn (Fn I64 -> I64)))))

(: run (impl (Fn (dyn (Fn -> I64 ! Abort)) -> I64)))
(define (run thunk)
  (unsafe-total thunk))

(handle Abort ((abort (lambda (value resume) (drop resume) value)))
  (run (lambda () (abort 1))))
