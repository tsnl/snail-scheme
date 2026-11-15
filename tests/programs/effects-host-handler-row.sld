(import
 (snail core base)
 (snail core io))

;; A handler of a host-bound effect, `Clock`, whose implementation performs
;; another, `Output-port`, with the rest of its row polymorphic (#456). The
;; body may perform anything in `e` besides the clock: here it writes too,
;; so `e` is `Console`.
(define (logged-clock (body (Fn → I64 ! Clock e))) (→ I64) (! Output-port e) (∀ (e))
  (handle Clock
      ((monotonic-nanoseconds (lambda () (write-line "the clock was read") 21)))
    (body)))

(define (main) (→ Unit) (! Output-port)

  (write-line
   (show (logged-clock (lambda () (+ (monotonic-nanoseconds) (monotonic-nanoseconds))))))
  (write-line (show (logged-clock (lambda ()
                                    (write-line "the body writes")
                                    (* 2 (monotonic-nanoseconds))))))
  (unit))
