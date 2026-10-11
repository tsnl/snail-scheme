;; The native CLI platform initializes this module and invokes main once.
;; Compilation, artifact paths, and execution are ordinary library operations.
(import (scheme base) (scheme process-context) (scheme write)
        (snail-scheme options) (snail-scheme native) (snail-scheme installation))

;; ---- Interpreter options and script arguments ----

(define options
  (make-args-spec
   '((key-val-list ("-I") "Prepend a library directory; later directories take priority." "DIRECTORY")
     (flag ("-h" "--help") "Show this help."))
   "snail-scheme" "Run a Scheme SCRIPT, passing all subsequent arguments to it."))

;; One prefix parse validates interpreter options and preserves the script tail.
;; The -I value list already has Chibi's last-supplied-first directory priority.
(define (main)
  (let* ((args (parse-options-prefix options (cdr (command-line))))
         (arguments (args-posargs args)))
    (cond ((args-ref args "-h") (display (options-help options)) 0)
          ((null? arguments) (error (options-help options)))
          (else
           (run-script (or (get-environment-variable "SNAIL_ROOT") installation-root)
                       (car arguments) (cdr arguments)
                       (args-ref args "-I"))))))
