;; File scopes own Chromium traces. Only completed calls emit spans; an initial
;; metadata event lets every span start with a comma.
(define-library (snail-scheme chromium-trace)
  (export trace with-trace-to)
  (import (scheme base) (scheme file) (scheme time) (scheme write))
  (begin

    ;; ---- File scopes and procedure decoration ----

    (define trace-output-port (make-parameter #f))

    (define (with-trace-to filename thunk)
      (if (not (procedure? thunk)) (error "with-trace-to: expected a procedure" thunk))
      (let ((port (open-output-file filename)))
        (initialize-trace-file port)
        (parameterize ((trace-output-port port))
          (call-with-values thunk
            (lambda results
              (finish-trace-file port)
              (apply values results))))))

    (define (trace name procedure)
      (if (not (string? name)) (error "trace: expected a string name" name))
      (if (not (procedure? procedure)) (error "trace: expected a procedure" procedure))
      (lambda arguments
        (let ((port (trace-output-port)))
          (if (not port) (error "trace: no active with-trace-to scope"))
          (call-with-trace-span name port procedure arguments))))

    ;; Capture the destination at invocation and emit only after normal return.
    ;; Aborted calls produce no span; abandoning a file scope skips finalization.
    (define (call-with-trace-span name port procedure arguments)
      (let ((start (current-jiffy)))
        (call-with-values (lambda () (apply procedure arguments))
          (lambda results
            (write-trace-span name start (current-jiffy) port)
            (apply values results)))))

    ;; ---- Chromium JSON events ----

    ;; The first array element names the Scheme thread lane.
    (define (initialize-trace-file port)
      (display "[\n{\"ph\":\"M\",\"pid\":1,\"tid\":1,\"name\":\"thread_name\"," port)
      (display "\"args\":{\"name\":\"Scheme\"}}" port))

    (define (finish-trace-file port)
      (display "\n]\n" port)
      (close-output-port port))

    ;; Convert without ratios or a potentially overflowing ticks * 1000000.
    ;; Chibi uses wall time; compiled programs use a monotonic clock.
    (define (jiffies->microseconds ticks)
      (let ((frequency (jiffies-per-second)))
        (+ (* (quotient ticks frequency) 1000000)
           (quotient (* (remainder ticks frequency) 1000000) frequency))))

    (define (write-trace-span name start finish port)
      (display ",\n{\"ph\":\"X\",\"pid\":1,\"tid\":1,\"name\":" port)
      (write-json-string name port)
      (display ",\"ts\":" port)
      (display (jiffies->microseconds start) port)
      (display ",\"dur\":" port)
      (display (jiffies->microseconds (if (< finish start) 0 (- finish start))) port)
      (display "}" port))

    (define (write-json-string text port)
      (display "\"" port)
      (let loop ((index 0))
        (if (< index (string-length text))
            (begin
              (write-json-character (string-ref text index) port)
              (loop (+ index 1)))))
      (display "\"" port))

    (define (write-json-character character port)
      (cond ((char=? character #\") (display "\\\"" port))
            ((char=? character #\\) (display "\\\\" port))
            ((< (char->integer character) 32)
             (let ((hex (number->string (char->integer character) 16)))
               (display "\\u" port)
               (display (substring "0000" (string-length hex) 4) port)
               (display hex port)))
            (else (display character port)))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (import (chibi json) (chibi temp-file) (snail-scheme test-utils))
    (export test-chromium-trace)
    (begin
      (define (trace-test-path directory name)
        (string-append directory "/" name ".json"))

      (define (trace-events filename)
        (call-with-port (open-input-file filename)
          (lambda (port) (vector->list (json-read port)))))

      (define (event-field event key) (cdr (assoc key event)))

      (define (trace-names filename)
        (map (lambda (event) (event-field event 'name)) (cdr (trace-events filename))))

      (define (test-trace-unbound)
        (let* ((called? #f)
               (procedure (trace "unbound" (lambda () (set! called? #t)))))
          (expect (guard (failure (else 'caught)) (procedure)) 'caught)
          (expect called? #f)
          (expect (guard (failure (else 'caught)) (trace 'name values)) 'caught)
          (expect (guard (failure (else 'caught)) (trace "name" 1)) 'caught)))

      (define (test-trace-values directory)
        (let ((path (trace-test-path directory "values"))
              (procedure (trace "values" values)) (port #f))
          (expect (call-with-values
                      (lambda ()
                        (with-trace-to
                         path (lambda () (set! port (trace-output-port)) (procedure 1 2 3))))
                    list) '(1 2 3))
          (expect (trace-output-port) #f)
          (expect (output-port-open? port) #f)
          (expect (trace-names path) '("values"))
          (expect (call-with-values
                      (lambda () (with-trace-to path procedure)) list) '())
          (expect (trace-names path) '("values"))))

      (define (test-trace-empty-file directory)
        (let ((path (trace-test-path directory "empty")))
          (expect (call-with-values (lambda () (with-trace-to path values)) list) '())
          (expect (length (trace-events path)) 1)
          (expect (event-field (car (trace-events path)) 'ph) "M")
          (expect (trace-names path) '())))

      (define (json-control-characters)
        (let loop ((code 31) (characters '()))
          (if (< code 0) (list->string characters)
              (loop (- code 1) (cons (integer->char code) characters)))))

      (define (test-trace-json)
        (let ((port (open-output-string)) (frequency (jiffies-per-second))
              (name (string-append "quote\" slash\\ λ" (json-control-characters))))
          (initialize-trace-file port)
          (write-trace-span name (* 2 frequency) (* 3 frequency) port)
          (write-trace-span "backward clock" 1 0 port)
          (display "\n]\n" port)
          (let* ((events (vector->list (json-read (open-input-string (get-output-string port)))))
                 (event (cadr events)))
            (expect (event-field event 'name) name)
            (expect (event-field event 'ph) "X")
            (expect (event-field event 'ts) 2000000)
            (expect (event-field event 'dur) 1000000)
            (expect (event-field (car (cddr events)) 'dur) 0))))

      (define (test-trace-errors directory)
        (let ((path (trace-test-path directory "error")) (port #f))
          (with-trace-to
           path (lambda ()
                  (set! port (trace-output-port))
                  (expect (guard (failure (else 'caught))
                            ((trace "failure"
                                    (lambda ()
                                      ((trace "completed" values))
                                      (error "expected failure"))))) 'caught)
                  ((trace "after" values))))
          (expect (trace-names path) '("completed" "after"))
          (expect (trace-output-port) #f)
          (expect (output-port-open? port) #f)))

      (define (test-trace-open-failure directory)
        (let ((called? #f))
          (expect (guard (failure (else 'caught))
                    (with-trace-to
                     (string-append directory "/absent/trace.json")
                     (lambda () (set! called? #t)))) 'caught)
          (expect called? #f)
          (expect (trace-output-port) #f)))

      (define (test-trace-nesting directory)
        (let ((outer (trace-test-path directory "outer"))
              (inner (trace-test-path directory "inner")))
          (with-trace-to
           outer
           (trace "outer"
                  (lambda ()
                    ((trace "before" values))
                    (with-trace-to inner (trace "inner" values))
                    ((trace "after" values)))))
          (expect (trace-names outer) '("before" "after" "outer"))
          (expect (trace-names inner) '("inner"))))

      (define (test-trace-escape directory)
        (let ((path (trace-test-path directory "escape")) (port #f))
          (with-trace-to
           path
           (lambda ()
             (set! port (trace-output-port))
             (expect (call/cc
                      (lambda (escape)
                        ((trace "escape"
                                (lambda ()
                                  ((trace "completed" values))
                                  (escape 'escaped)))))) 'escaped)
             ((trace "after" values))))
          (expect (trace-names path) '("completed" "after"))
          (expect (trace-output-port) #f)
          (expect (output-port-open? port) #f)))

      (define (test-chromium-trace)
        (test-trace-unbound)
        (test-trace-json)
        (call-with-temp-dir
         "snail-chromium-trace"
         (lambda (directory preserve)
           (test-trace-values directory)
           (test-trace-empty-file directory)
           (test-trace-errors directory)
           (test-trace-open-failure directory)
           (test-trace-nesting directory)
           (test-trace-escape directory))))))
   (else)))
