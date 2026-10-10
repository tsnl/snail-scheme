;; The native CLI platform initializes this module and invokes main once.
;; Compilation, artifact paths, and execution are ordinary library operations.
(import (scheme base) (scheme process-context)
        (snail-scheme native) (snail-scheme installation))

;; ---- Interpreter options and script arguments ----

(define usage "usage: snail-scheme [-I DIRECTORY ...] [--] SCRIPT [ARGUMENT ...]")

;; Each -I prepends, as in Chibi. Once the script or -- is reached, the
;; remaining argv stays literal, including options belonging to the script.
(define (parse-command-line arguments)
  (let loop ((remaining arguments) (directories '()))
    (if (null? remaining) (values directories remaining)
        (let ((argument (car remaining)))
          (cond ((string=? argument "-I")
                 (if (null? (cdr remaining)) (error "-I requires a directory" usage))
                 (loop (cddr remaining) (cons (cadr remaining) directories)))
                ((and (> (string-length argument) 2) (string=? (substring argument 0 2) "-I"))
                 (loop (cdr remaining)
                       (cons (substring argument 2 (string-length argument)) directories)))
                ((string=? argument "--") (values directories (cdr remaining)))
                ((and (> (string-length argument) 0) (char=? (string-ref argument 0) #\-))
                 (error "unknown option" argument usage))
                (else (values directories remaining)))))))

(define (main)
  (let-values (((directories arguments) (parse-command-line (cdr (command-line)))))
    (if (null? arguments) (error usage))
    (run-script (or (get-environment-variable "SNAIL_ROOT") installation-root)
                (car arguments) (cdr arguments) directories)))
