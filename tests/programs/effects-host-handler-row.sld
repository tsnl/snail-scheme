(import
 (snail core base)
 (snail core io))

;; A handler of a host-bound effect, `clock`, whose implementation performs
;; another, `console`, with the rest of its row polymorphic (#456). The
;; body may perform anything in `e` besides the clock: here it writes too,
;; so `e` is `console`.
(: logged-clock (All (e) (-> (-> I64 ! clock e) I64 ! console e)))
(define (logged-clock body)
  (handle clock
      ((monotonic-nanoseconds (lambda () (write-line "the clock was read") 21)))
    (body)))

(write-line (show (logged-clock (lambda () (+ (monotonic-nanoseconds) (monotonic-nanoseconds))))))
(write-line (show (logged-clock (lambda ()
                                  (write-line "the body writes")
                                  (* 2 (monotonic-nanoseconds))))))
