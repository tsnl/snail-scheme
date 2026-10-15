;; The runner prepends the unchanged source definitions of the handler and
;; compiler-abort. This is an independent Chez control for the propagation tests.

(define original-trace 0)
(define (original-step digit) (set! original-trace (+ (* 10 original-trace) digit)))
(define (original-callback)
  (original-step 2)
  (compiler-abort))
(define original-failure
  (with-exception-handling
   (lambda ()
     (original-step 1)
     (original-callback)
     (original-step 3)
     #t)))
(unless (and (not original-failure) (= original-trace 12))
  (error 'original-probe "effects continued after abort"))

(set! original-trace 0)
(define original-nested
  (with-exception-handling
   (lambda ()
     (original-step 1)
     (let ((inner (with-exception-handling original-callback)))
       (when inner (error 'original-probe "inner abort was not false"))
       (original-step 3)
       (compiler-abort)
       (original-step 4)
       #t))))
(unless (and (not original-nested) (= original-trace 123))
  (error 'original-probe "nested handler did not restore outer abort"))

(define original-false
  (with-exception-handling
   (lambda ()
     (not (with-exception-handling (lambda () #f))))))
(unless original-false (error 'original-probe "false was not a normal value"))
(define original-sink-entered #f)
(define (original-sink value) (set! original-sink-entered #t) value)
(define original-argument-abort
  (with-exception-handling (lambda () (original-sink (compiler-abort)))))
(unless (and (not original-argument-abort) (not original-sink-entered))
  (error 'original-probe "enclosing operation executed after argument abort"))
(display "PASS original continuation effect and nesting controls\n")
