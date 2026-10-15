;; These probes exercise explicit propagation, not a complete compiler run.

;; ---- A failed call preserves earlier effects and skips later effects ----

(define (probe-step trace digit)
  (ref-set! trace (+ (* 10 (ref-get trace)) digit)))
(: probe-failing-callback (-> (Ref I64) (CompilerResult I64)))
(define (probe-failing-callback trace)
  (probe-step trace 2)
  (compiler-abort-result))
(: probe-call-callback (-> (Ref I64) (-> (Ref I64) (CompilerResult I64)) (CompilerResult Bool)))
(define (probe-call-callback trace callback)
  (probe-step trace 1)
  (match (callback trace)
    ((compiler-failure) (compiler-failure))
    ((compiler-success value)
     (probe-step trace 3)
     (compiler-success (= value 7)))))
(define (probe-failure-after-mutation)
  (let* ((trace (ref 0))
         (result (compiler-with-exception-handling
                   (lambda () (probe-call-callback trace probe-failing-callback)))))
    (and (not result) (= (ref-get trace) 12)
         (not (ref-get compiler-handler-active)))))
(define (probe-success-after-mutation)
  (let* ((trace (ref 0))
         (result (compiler-with-exception-handling
                   (lambda ()
                     (probe-call-callback trace
                       (lambda (trace) (probe-step trace 2) (compiler-success 7)))))))
    (and result (= (ref-get trace) 123) (not (ref-get compiler-handler-active)))))
(define (probe-sink entered value)
  (ref-set! entered #t)
  value)
(define (probe-argument-abort)
  (let* ((entered (ref #f))
         (result (compiler-with-exception-handling
                   (lambda ()
                     (match (ann (compiler-abort-result) (CompilerResult Bool))
                       ((compiler-failure) (compiler-failure))
                       ((compiler-success value) (compiler-success (probe-sink entered value))))))))
    (and (not result) (not (ref-get entered)) (not (ref-get compiler-handler-active)))))

;; ---- Inner failure is a normal false result for the outer computation ----

(: probe-nested-inner (-> (Ref I64) (CompilerResult Bool)))
(define (probe-nested-inner trace)
  (probe-step trace 2)
  (compiler-abort-result))
(: probe-nested-outer (-> (Ref I64) (Ref Bool) (CompilerResult Bool)))
(define (probe-nested-outer trace restored)
  (probe-step trace 1)
  (let ((inner (compiler-with-exception-handling (lambda () (probe-nested-inner trace)))))
    (ref-set! restored (and (not inner) (ref-get compiler-handler-active)))
    (probe-step trace 3)
    (compiler-abort-result)))
(define (probe-nested-handlers)
  (let* ((trace (ref 0)) (restored (ref #f))
         (result (compiler-with-exception-handling
                   (lambda () (probe-nested-outer trace restored)))))
    (and (not result) (ref-get restored) (= (ref-get trace) 123)
         (not (ref-get compiler-handler-active)))))
(define (probe-false-is-success)
  (compiler-with-exception-handling
    (lambda ()
      (let ((inner (compiler-with-exception-handling (lambda () (compiler-success #f)))))
        (compiler-success (and (not inner) (ref-get compiler-handler-active)))))))

(if (and (probe-failure-after-mutation) (probe-success-after-mutation) (probe-argument-abort)
         (probe-nested-handlers) (probe-false-is-success)
         (not (ref-get compiler-handler-active)))
    42 0)
