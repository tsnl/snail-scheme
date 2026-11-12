(import
 (snail core base)
 (snail core io))

;; A handler of a host-bound effect, `clock`, whose implementation performs
;; another, `output-port`, with the rest of its row polymorphic (#456). The
;; body may perform anything in `e` besides the clock: here it writes too,
;; so `e` is `console`.
(define (logged-clock (body (FnOnce → I64 ! clock e))) (→ I64) (! output-port e) (∀ e)
  (handle clock
      ((monotonic-nanoseconds (lambda () (write-line "the clock was read") 21)))
    (body)))

(define main
  (lambda ()
    (write-line
     (show (logged-clock (lambda () (+ (monotonic-nanoseconds) (monotonic-nanoseconds))))))
    (write-line (show (logged-clock (lambda ()
                                      (write-line "the body writes")
                                      (* 2 (monotonic-nanoseconds))))))
    (unit)))
