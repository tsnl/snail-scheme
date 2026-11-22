(import
 (snail core base)
 (snail core io))

;; A handler of a host-bound effect, `clock`, whose implementation performs
;; another, `output-port`, with the rest of its row polymorphic (#456). The
;; body may perform anything in `e` besides the clock: here it writes too,
;; so `e` is `console`.
(define (logged-clock (out OutputPort) (body (Fn → I64 ! mut e))) (→ I64) (! mut e) (∀ (e))
  (handle clock
      ((monotonic-nanoseconds (lambda () (write-line out "the clock was read") 21)))
    (body)))

(define (main (out OutputPort)) (→ Unit) (! mut)

  (write-line out
   (show (logged-clock out (lambda () (+ (monotonic-nanoseconds clock) (monotonic-nanoseconds clock))))))
  (write-line out (show (logged-clock out (lambda ()
                                    (write-line out "the body writes")
                                    (* 2 (monotonic-nanoseconds clock))))))
  (unit))
