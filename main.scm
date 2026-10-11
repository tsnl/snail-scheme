;; The native CLI platform initializes this module and invokes main once.
;; Compilation, artifact paths, and execution are ordinary library operations.
(import (scheme base) (scheme process-context) (scheme write)
        (snail-scheme options) (snail-scheme native) (snail-scheme installation)
        (snail-scheme chromium-trace) (only (snail-scheme build-host) same-file?))

;; ---- Interpreter options and script arguments ----

(define options
  (make-args-spec
   '((key-val-list ("-I") "Prepend a library directory; later directories take priority." "DIRECTORY")
     (flag ("-h" "--help") "Show this help."))
   "snail-scheme" "Run a Scheme SCRIPT, passing all subsequent arguments to it."))

;; Interpreter parsing and help finish before this operation opens a trace.
;; Protect the script from trace-output aliases before compilation starts.
(define (run-interpreter-script args)
  (let* ((arguments (args-posargs args)) (script (car arguments))
         (trace-file (string-append script ".trace.json")))
    (if (same-file? script trace-file) (error "trace file must not replace script" script))
    (with-chromium-trace-to trace-file
                            (lambda ()
                              (run-script (or (get-environment-variable "SNAIL_ROOT") installation-root)
                                          script (cdr arguments) (args-ref args "-I"))))))

;; One prefix parse preserves the script tail. Its -I values already have
;; Chibi's last-supplied-first directory priority.
(define (main)
  (let ((args (parse-options-prefix options (cdr (command-line)))))
    (cond ((args-ref args "-h") (display (options-help options)) 0)
          ((null? (args-posargs args)) (error (options-help options)))
          (else (run-interpreter-script args)))))
