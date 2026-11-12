(import
 (snail core base)
 (snail core io)
 (snail core dynamic))

(struct Point
  ((x I64)))

(struct Reports
  ((count I64)))

(define (integer (value Any)) (→ I64) (! dyn-cast) value)

;; Inference propagates the conversion effect; explicit syntax obeys the
;; same rule. Calling this function is checked at each enclosing boundary.
(define inferred (lambda (value) (type-convert (ann value Any) I64)))

(define (fallback (value Any)) (→ I64)
  (handle dyn-cast ((conversion-failed (lambda (_) -1))) (integer value)))

(define (same (value Any)) (→ Any) (type-convert value Any))

(define main
  (lambda ()
    (write-line (show (fallback 42)))
    (write-line (show (fallback "bad")))
    (write-line (show (match (try-convert (ann 7 Any) I64) ((Ok value) value) ((Err _) -1))))
    (write-line (show (match (try-convert (ann "bad" Any) I64) ((Ok _) #f) ((Err _) #t))))
    (write-line (show (match (try-convert (ann (Point 9) Any) Point)
                        ((Ok point) (● point x)) ((Err _) -1))))
    (write-line
     (show (match (try-convert (ann (lambda (x) (+ x 1)) (Fn I64 → I64)) (Fn I64 → I64))
             ((Ok function) (function 9)) ((Err _) -1))))
    (write-line (show (match (try-dynamic (lambda () (inferred "bad")))
                        ((Ok _) #f) ((Err _) #t))))
    ;; Catching does not resume the failed conversion. An outer handler may
    ;; catch a rethrow from the inner handler.
    (handle dyn-cast
        ((conversion-failed (lambda (_) (write-line "outer caught"))))
      (handle dyn-cast
          ((conversion-failed (lambda (error) (absurd (conversion-failed error)))))
        (integer "bad")
        (write-line "unreachable")))
    ;; A narrowing check cannot cancel merely because its answer is repackaged.
    (handle dyn-cast ((conversion-failed (lambda (_) (write-line "adjacent checked"))))
      (type-convert (type-convert (ann "bad" Any) I64) Any)
      (write-line "unreachable"))
    (handle dyn-cast ((conversion-failed (lambda (_) (write-line "let checked"))))
      (let ((value (type-convert (ann "bad" Any) I64)))
        (ann value Any))
      (write-line "unreachable"))
    (handle dyn-cast ((conversion-failed (lambda (_) (write-line "unexpected"))))
      (write-line (show (type-convert (type-convert (ann 8 I64) Any) I64))))
    ;; An interactive client gets a report and a failure value, and can run
    ;; another evaluation. Capture output-port output so origins remain portable.
    (let ((reported (Reports 0)))
      (handle output-port
          ((write-string (lambda (_) (set! (● reported count) (+ 1 (● reported count))))))
        (run-dynamic (lambda () (integer "bad"))))
      (write-line (show (> (● reported count) 0))))
    (write-line (show (match (run-dynamic (lambda () (integer 43)))
                        ((Ok value) value) ((Err _) -1))))
    (write-line (show (type-test (same 7) I64)))
    (unit)))
