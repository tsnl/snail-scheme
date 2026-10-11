;; The native CLI platform initializes this module and invokes main once.
;; Compilation, artifact paths, and execution are ordinary library operations.
(import (scheme base) (scheme process-context) (scheme write)
        (snail-scheme options) (snail-scheme native) (snail-scheme installation))

;; ---- Interpreter options and script arguments ----

(define usage "usage: snail-scheme [OPTIONS] [--] SCRIPT [ARGUMENT ...]")
(define options
  (list (option "-I" 'key-val-list "Prepend a library directory; later directories take priority."
                "DIRECTORY")
        (option '("-h" "--help") 'flag "Show this help.")))

;; One prefix parse validates interpreter options and preserves the script tail.
;; The -I value list already has Chibi's last-supplied-first directory priority.
(define (main)
  (let* ((args (parse-options-prefix options (cdr (command-line)) usage))
         (arguments (args-posargs args)))
    (cond ((args-ref args "-h") (display (options-help options usage)) 0)
          ((null? arguments) (error usage))
          (else
           (run-script (or (get-environment-variable "SNAIL_ROOT") installation-root)
                       (car arguments) (cdr arguments)
                       (args-ref args "-I"))))))
