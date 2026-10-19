;; Coarse host progress goes to stderr immediately. Importing is quiet;
;; callers choose operation boundaries, never individual expression visits.
(define-library (lofi host log)
  (export log-message call-with-log-phase log-enabled?)
  (import
   (scheme base)
   (scheme process-context)
   (scheme time)
   (scheme write))
  (begin

    ;; ---- Live progress ----

    (define log-enabled?
      (make-parameter (not (member (get-environment-variable "SNAIL_LOG") '("off" "0")))))
    (define (log-message . parts)
      (when (log-enabled?)
        (let ((port (current-error-port)))
          (display "[lofi] " port)
          (for-each (lambda (part) (display part port)) parts)
          (newline port)
          (flush-output-port port))))
    (define (call-with-log-phase name thunk)
      (if (not (log-enabled?)) (thunk)
          (let ((start (current-jiffy)))
            (log-message name " started")
            (call-with-values thunk
              (lambda results
                (log-message name " done ("
                             (quotient (* 1000 (max 0 (- (current-jiffy) start))) (jiffies-per-second)) " ms)")
                (apply values results)))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-log)
    (import
     (lofi host test-utils)
     (only (srfi 130) string-contains))
    (begin
      (define (test-log-progress)
        (let ((port (open-output-string)))
          (parameterize ((current-error-port port) (log-enabled? #t))
            (expect (call-with-values
                        (lambda ()
                          (call-with-log-phase "checking"
                                               (lambda ()
                                                 (expect (get-output-string port) "[lofi] checking started\n")
                                                 (values 1 2)))) list) '(1 2))
            (expect (if (string-contains (get-output-string port) "[lofi] checking done (") #t #f) #t)
            (expect (call-with-values (lambda () (call-with-log-phase "empty" values)) list) '()))))
      (define (test-log-quiet-and-failure)
        (let ((port (open-output-string)))
          (parameterize ((current-error-port port) (log-enabled? #f))
            (log-message "hidden")
            (expect (call-with-log-phase "hidden" (lambda () 42)) 42)
            (expect (get-output-string port) ""))
          (parameterize ((current-error-port port) (log-enabled? #t))
            (expect (guard (failure (else 'caught))
                      (call-with-log-phase "failure" (lambda () (error "expected")))) 'caught)
            (expect (get-output-string port) "[lofi] failure started\n"))))
      (define (test-log)
        (run-test test-log-progress)
        (run-test test-log-quiet-and-failure))))
   (else)))
