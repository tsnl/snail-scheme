;; The native CLI platform initializes this module and invokes main once.
;; Compilation, artifact paths, and execution are ordinary library operations.
(import (scheme base) (scheme process-context)
        (snail-scheme options) (snail-scheme native) (snail-scheme installation))

;; ---- Interpreter options and script arguments ----

(define usage "usage: snail-scheme [-I DIRECTORY ...] [--] SCRIPT [ARGUMENT ...]")

;; Option syntax belongs to the reusable library. This interpreter chooses
;; Chibi's policy: each -I prepends, so reverse the directory occurrences.
(define (main)
  (let-values (((options arguments) (parse-options '(("-I" . #t)) (cdr (command-line)) usage)))
    (if (null? arguments) (error usage))
    (run-script (or (get-environment-variable "SNAIL_ROOT") installation-root)
                (car arguments) (cdr arguments) (reverse (map cdr options)))))
