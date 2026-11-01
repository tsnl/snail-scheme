(import
 (snail core base)
 (snail core io)
 (snail core dynamic))

(struct Point
  ((x I64)))

(: integer (-> Any I64 ! dyn-tc))
(define (integer value) value)

;; Inference propagates the conversion effect; explicit syntax obeys the
;; same rule. Calling this function is checked at each enclosing boundary.
(define (inferred value) (type-convert (ann value Any) I64))

(: fallback (-> Any I64))
(define (fallback value)
  (handle dyn-tc ((conversion-failed (lambda (_) -1))) (integer value)))

(write-line (show (fallback 42)))
(write-line (show (fallback "bad")))
(write-line (show (match (try-convert (ann 7 Any) I64) ((Ok value) value) ((Err _) -1))))
(write-line (show (match (try-convert (ann "bad" Any) I64) ((Ok _) #f) ((Err _) #t))))
(write-line (show (match (try-convert (ann (Point 9) Any) Point)
                    ((Ok point) (Point-x point)) ((Err _) -1))))
(write-line (show (match (try-convert (ann (lambda (x) (+ x 1)) (-> I64 I64)) (-> I64 I64))
                    ((Ok function) (function 9)) ((Err _) -1))))
(write-line (show (match (try-dynamic (lambda () (inferred "bad")))
                    ((Ok _) #f) ((Err _) #t))))

;; Catching does not resume the failed conversion. An outer handler may
;; catch a rethrow from the inner handler.
(handle dyn-tc
    ((conversion-failed (lambda (_) (write-line "outer caught"))))
  (handle dyn-tc
      ((conversion-failed (lambda (error) (absurd (conversion-failed error)))))
    (integer "bad")
    (write-line "unreachable")))

;; A narrowing check cannot cancel merely because its answer is repackaged.
(handle dyn-tc ((conversion-failed (lambda (_) (write-line "adjacent checked"))))
  (type-convert (type-convert (ann "bad" Any) I64) Any)
  (write-line "unreachable"))
(handle dyn-tc ((conversion-failed (lambda (_) (write-line "let checked"))))
  (let ((value (type-convert (ann "bad" Any) I64)))
    (ann value Any))
  (write-line "unreachable"))
(handle dyn-tc ((conversion-failed (lambda (_) (write-line "unexpected"))))
  (write-line (show (type-convert (type-convert (ann 8 I64) Any) I64))))

;; An interactive client gets a report and a failure value, and can run
;; another evaluation. Capture console output so origins remain portable.
(let ((reported (ref 0)))
  (handle console
      ((console-write (lambda (_) (ref-set! reported (+ 1 (ref-get reported)))))
       (console-read (lambda () -1)))
    (run-dynamic (lambda () (integer "bad"))))
  (write-line (show (> (ref-get reported) 0))))
(write-line (show (match (run-dynamic (lambda () (integer 43)))
                    ((Ok value) value) ((Err _) -1))))

(: same (-> Any Any))
(define (same value) (type-convert value Any))
(write-line (show (type-test (same 7) I64)))
