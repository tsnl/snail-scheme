;; The lofi command: compile, run, or print the WebAssembly text of a program.
(import
 (scheme base)
 (scheme process-context)
 (scheme write)
 (chibi filesystem)
 (chibi pathname)
 (chibi process)
 (lofi compiler build))

;; ---- Requests ----

(define usage "usage: lofi compile|run|wat [--release] [-I DIR] [-o OUTPUT] SOURCE [ARGUMENT ...]")



(define (absolute path)
  (if (path-absolute? path) path (path-join (current-directory) path)))

;; Returns an association list of the options, the source and its arguments.
(define (request arguments)
  (unless (and (pair? arguments) (member (car arguments) '("compile" "run" "wat"))) (error usage))
  (let loop ((rest (cdr arguments)) (options (list (cons 'action (car arguments)))))
    (cond ((null? rest) (error usage))
          ((string=? (car rest) "--release") (loop (cdr rest) (cons '(release . #t) options)))
          ((member (car rest) '("-I" "-o"))
           (when (null? (cdr rest)) (error usage))
           (loop (cddr rest) (cons (cons (if (string=? (car rest) "-I") 'library 'output) (absolute (cadr rest))) options)))
          (else (append options (list (cons 'source (absolute (car rest))) (cons 'arguments (cdr rest))))))))

(define (option options name default)
  (let ((entry (assq name options))) (if entry (cdr entry) default)))

(define (directories root options)
  (append (reverse (map cdr (filter-library options))) (list (path-join root "lib"))))

(define (filter-library options)
  (let loop ((options options) (out '()))
    (cond ((null? options) out)
          ((eq? (caar options) 'library) (loop (cdr options) (cons (car options) out)))
          (else (loop (cdr options) out)))))

;; ---- Actions ----

(define (perform root options)
  (let ((source (option options 'source #f)) (action (option options 'action "run")))
    (if (string=? action "wat")
        (begin (write-string (compile->wat root (directories root options) source)) 0)
        (let ((output (or (option options 'output #f) (path-join root "build/lofi-run/program.wasm"))))
          (build-program root (directories root options) source output (option options 'release #f))
          (if (string=? action "compile")
              0
              (run-program root output (option options 'arguments '())))))))

;; The program inherits standard input and output; its status is returned.
(define (run-program root program arguments)
  (let ((status (cadr (apply system (or (get-environment-variable "NODE") "node") "--no-warnings"
                             (path-join root "scripts/run-lofi.mjs") program arguments))))
    (quotient status 256)))

(define (report failure)
  (let ((port (current-error-port)))
    (display "lofi: " port)
    (if (error-object? failure)
        (begin (display (error-object-message failure) port)
               (for-each (lambda (irritant) (display " " port) (write irritant port)) (error-object-irritants failure)))
        (write failure port))
    (newline port)
    1))

(let ((arguments (command-line)))
  (exit (guard (failure (#t (report failure)))
               (perform (cadr arguments) (request (cddr arguments))))))
