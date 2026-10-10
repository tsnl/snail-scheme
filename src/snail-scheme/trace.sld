;; Coarse, always-on profiling shared by compiler modules and user programs.
;; Decorate complete operations, not recursive loops: the wrapper must return
;; to close its span. Tracing writes no program output and preserves values.
(define-library (snail-scheme trace)
  (export define-traced call-with-trace)
  (import (scheme base))
  (begin
    ;; ---- Procedure decoration ----

    (define-syntax define-traced
      (syntax-rules ()
        ((_ (name . formals) body ...)
         (define (name . formals)
           (call-with-trace (symbol->string 'name) (lambda () body ...)))))))
  (cond-expand
   (snail-scheme
    (import (only (snail-scheme core) %trace-begin %trace-end))
    (begin
      ;; Generated programs do not implement dynamic-wind yet. This adapter
      ;; supports ordinary returns and terminal errors; continuation escape
      ;; followed by more execution can leave incorrectly nested spans.
      (define (call-with-trace name thunk)
        (%trace-begin name)
        (call-with-values thunk
          (lambda results (%trace-end) (apply values results))))))
   (else
    (import (scheme write) (scheme process-context)
            (only (chibi time) get-time-of-day timeval-seconds timeval-microseconds)
            (only (chibi filesystem) create-directory* open open/write open/create
                  open/exclusive open-output-file-descriptor file-exists?)
            (only (chibi io) set-file-position! seek/end)
            (only (chibi process) current-process-id))
    (begin
      ;; ---- Chibi host adapter ----
      ;; The host compiler runs on one Scheme thread. Its trace uses one lane;
      ;; Rust's shared recorder supplies thread lanes for native host code.

      (define trace-port #f)
      (define trace-failed? #f)
      (define trace-first? #t)
      (define trace-start 0)

      (define (call-with-trace name thunk)
        (dynamic-wind (lambda () (trace-event name "B"))
            thunk (lambda () (trace-event "" "E"))))

      (define (trace-event name phase)
        (if (not trace-failed?)
            (guard (error (else (trace-failure error)))
              (if (not trace-port) (open-trace))
              (write-trace-event name phase))))

      (define (trace-failure error)
        (set! trace-failed? #t)
        (if trace-port (guard (ignored (else #f)) (close-output-port trace-port)))
        (guard (ignored (else #f))
          (display "snail-trace: " (current-error-port))
          (write error (current-error-port)) (newline (current-error-port))))

      (define (open-trace)
        (let ((directory (or (get-environment-variable "SNAIL_TRACE_DIR") "build/traces")))
          (if (not (create-directory* directory)) (error "cannot create trace directory" directory))
          (set! trace-port (open-unique-trace directory 0))
          (set! trace-start (trace-microseconds))
          (display "[]" trace-port) (flush-output-port trace-port)))

      (define (open-unique-trace directory serial)
        (let* ((path (string-append directory "/scheme-" (number->string (current-process-id))
                                    "-" (number->string serial) ".json"))
               (fd (open path (+ open/write open/create open/exclusive) #o600)))
          (cond (fd (open-output-file-descriptor fd))
                ((file-exists? path) (open-unique-trace directory (+ serial 1)))
                (else (error "cannot create trace file" path)))))

      ;; Chibi's standard jiffy is a wall-clock millisecond. Its host adapter
      ;; exposes microseconds directly; wall-clock adjustments still apply.
      (define (trace-microseconds)
        (let ((time (car (get-time-of-day))))
          (+ (* (timeval-seconds time) 1000000) (timeval-microseconds time))))

      ;; Rewrite the closing bracket after each event. Seeking from EOF uses
      ;; bytes and remains correct for labels containing multibyte characters.
      (define (write-trace-event name phase)
        (let ((microseconds (- (trace-microseconds) trace-start)))
          (set-file-position! trace-port -1 seek/end)
          (if (not trace-first?) (display ",\n" trace-port))
          (display "{\"name\":" trace-port) (write-json-string name trace-port)
          (display ",\"cat\":\"snail\",\"ph\":" trace-port) (write-json-string phase trace-port)
          (display ",\"ts\":" trace-port) (display microseconds trace-port)
          (display ",\"pid\":" trace-port) (display (current-process-id) trace-port)
          (display ",\"tid\":1}]" trace-port) (flush-output-port trace-port)
          (set! trace-first? #f)))

      (define (write-json-string text port)
        (write-char #\" port)
        (string-for-each (lambda (character) (write-json-character character port)) text)
        (write-char #\" port))

      (define (write-json-character character port)
        (cond ((char=? character #\") (display "\\\"" port))
              ((char=? character #\\) (display "\\\\" port))
              ((< (char->integer character) 32)
               (let ((hex (number->string (char->integer character) 16)))
                 (display "\\u" port) (display (make-string (- 4 (string-length hex)) #\0) port)
                 (display hex port)))
              (else (write-char character port)))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (import (snail-scheme test-utils))
    (export test-trace)
    (begin
      (define-traced (trace-values . values-list) (apply values values-list))
      (define-traced (trace-error) (error "expected trace test error"))
      (define (test-trace)
        (expect (call-with-values (lambda () (trace-values 1 2)) list) '(1 2))
        (expect (call-with-values (lambda () (trace-values)) list) '())
        (expect (guard (error (else 'caught)) (trace-error)) 'caught))))
   (else)))
