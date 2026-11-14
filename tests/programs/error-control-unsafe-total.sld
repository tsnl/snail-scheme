(import
 (snail core base))

;; unsafe-total discards its thunk's row, so nothing after it would test
;; for a yield.
(effect Abort
  ((ctl abort (Fn I64 → I64))))

(define (run (thunk (Fn → I64 ! Abort))) (→ I64)
  (unsafe-total thunk))

(define (main) (→ Unit)

  (handle Abort ((abort (lambda (value resume) value)))
    (run (lambda () (abort 1))))
  (unit))
