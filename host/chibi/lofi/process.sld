;; Synchronous native tool invocation. Ordinary files capture stdout and
;; stderr, so the parent waits without pipes or borrowed descriptor owners.
(define-library (lofi process)
  (export capture-process)
  (import
   (scheme base)
   (scheme cxr)
   (scheme file)
   (scheme process-context)
   (scheme write)
   (only (chibi io) port->string)
   (only (chibi ast) errno integer->error-string)
   (chibi filesystem)
   (chibi process))
  (begin

    ;; ---- Capture ownership ----

    (define capture-count 0)

    (define (capture-directory)
      (set! capture-count (+ capture-count 1))
      (let ((directory (string-append (or (get-environment-variable "TMPDIR") "/tmp")
                                      "/lofi-command-" (number->string (current-process-id)) "-" (number->string capture-count))))
        (cond ((create-directory directory #o700) directory)
              ((file-link-status directory) (capture-directory))
              (else (error "cannot create tool capture directory" directory)))))

    (define (with-capture-directory use)
      (let ((directory (capture-directory)) (failed? #t))
        (dynamic-wind
            (lambda () #f)
            (lambda () (let ((result (use directory))) (set! failed? #f) result))
            (lambda ()
              (guard (failure (failed? #f) (else (raise failure)))
                (delete-file-hierarchy directory))))))

    (define (tool-argument? value)
      (and (string? value)
           (let loop ((index 0))
             (or (= index (string-length value))
                 (and (not (zero? (char->integer (string-ref value index)))) (loop (+ index 1)))))))

    (define (capture-process arguments)
      (unless (and (list? arguments) (pair? arguments)) (error "expected a nonempty tool argument list" arguments))
      (for-each (lambda (argument)
                  (unless (tool-argument? argument)
                    (error "expected a tool argument without NUL" argument)))
                arguments)
      (when (or (zero? (string-length (car arguments))) (char=? (string-ref (car arguments) 0) #\-))
        (error "expected a nonempty tool name without a leading dash" (car arguments)))
      (with-capture-directory
       (lambda (directory)
         (let* ((out (string-append directory "/stdout")) (err (string-append directory "/stderr"))
                (status (capture-status arguments out err)))
           (list (call-with-input-file out port->string) (call-with-input-file err port->string) status)))))

    ;; ---- Child process ----

    ;; Chibi 0.12's pipe helper raw-closes managed descriptors without
    ;; retiring their owners; later GC can close a reused descriptor. Its
    ;; dup2 binding also misreports successful nonzero destinations. Let
    ;; POSIX sh own redirection instead. The script is CONSTANT: every path
    ;; and argument is passed separately, never parsed as shell source.
    (define redirect-script
      "exec </dev/null >\"$1\" 2>\"$2\"; shift 2; exec \"$@\"")

    (define (capture-status arguments output error-output)
      (flush-output-port (current-output-port))
      (flush-output-port (current-error-port))
      (let ((pid (fork)))
        (cond ((< pid 0) (error "cannot fork tool" arguments))
              ((zero? pid)
               ;; Never unwind through the parent's directory cleanup.
               (guard (failure (else (emergency-exit 127)))
                 (execute "/bin/sh" (append (list "sh" "-c" redirect-script "lofi-capture" output error-output) arguments))
                 (emergency-exit 127)))
              (else (wait-for-tool pid)))))

    (define (wait-for-tool pid)
      (let* ((result (waitpid pid 0)) (code (errno)))
        (cond ((= (car result) pid) (cadr result))
              ;; EINTR is 4 on the supported Linux and macOS hosts.
              ((= code 4) (wait-for-tool pid))
              (else (error "cannot wait for tool" pid (integer->error-string code))))))
    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-process)
    (import
     (only (chibi ast) gc)
     (lofi testing))
    (begin
      ;; Several simultaneous readers cover descriptor numbers formerly
      ;; owned by both used and discarded pipe ends.
      (define (expect-open-readers file text count ports)
        (if (zero? count)
            (begin (gc) (for-each (lambda (in) (expect (equal? (read-string (string-length text) in) text) #t)) ports))
            (call-with-input-file file
              (lambda (in) (expect-open-readers file text (- count 1) (cons in ports))))))

      (define (test-process root)
        (let ((fixture (string-append root "/tests/process-capture.mjs")))
          (expect (capture-process (list "node" fixture "args" "a b" "it's \"quoted\"" "" "$(false); `false`"))
                  (list "a b\nit's \"quoted\"\n\n$(false); `false`" "" 0))
          (expect (capture-process (list "node" fixture "streams")) (list "stdin EOF; no newline" (make-string 1048576 #\e) (* 7 256)))
          (expect (guard (failure (else 'rejected)) (capture-process (list "true" (string #\a (integer->char 0) #\b)))) 'rejected)
          (expect (caddr (capture-process '("/lofi/nonexistent/tool"))) (* 127 256))
          (with-capture-directory
           (lambda (directory)
             (let ((file (string-append directory "/large")) (text (make-string 1048576 #\x)))
               (call-with-output-file file (lambda (out) (write-string text out)))
               (do ((i 0 (+ i 1))) ((= i 10)) (capture-process '("true")))
               (expect-open-readers file text 4 '()))))))))
   (else)))
