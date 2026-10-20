;; Command line for the redesigned compiler: compile or run one program.
(import
 (scheme base)
 (scheme process-context)
 (scheme write)
 (chibi filesystem)
 (lofi host process)
 (lofi compiler build))

;; ---- Requests ----

(define (request arguments)
  (unless (and (pair? arguments) (member (car arguments) '("compile" "run" "wat")))
    (error "usage: lofi-next compile|run|wat [--release] [-I DIR] [-o OUTPUT] SOURCE [ARGUMENT ...]"))
  (let loop ((rest (cdr arguments)) (options (list (cons 'action (car arguments)))))
    (cond ((null? rest) (error "a source file is required"))
          ((string=? (car rest) "--release") (loop (cdr rest) (cons '(release . #t) options)))
          ((member (car rest) '("-I" "-o"))
           (loop (cddr rest) (cons (cons (if (string=? (car rest) "-I") 'library 'output) (absolute-path (cadr rest))) options)))
          (else (append options (list (cons 'source (absolute-path (car rest))) (cons 'arguments (cdr rest))))))))

(define (directories root options)
  (append (map cdr (filter-library options)) (list (path-join root "lib"))))

(define (filter-library options)
  (let loop ((options options) (out '()))
    (cond ((null? options) (reverse out))
          ((eq? (caar options) 'library) (loop (cdr options) (cons (car options) out)))
          (else (loop (cdr options) out)))))

;; ---- Actions ----

(define (perform root options)
  (let ((source (option-ref options 'source #f)) (action (option-ref options 'action "run")))
    (cond ((string=? action "wat") (display (compile->wat (directories root options) source)) 0)
          (else
           (let* ((output (or (option-ref options 'output #f)
                              (path-join (make-build-directory (path-join root "build/lofi-next") "run-") "program.wasm"))))
             (build-program root (directories root options) source output (option-ref options 'release #f))
             (if (string=? action "compile")
                 0
                 (run-program root output (option-ref options 'arguments '()))))))))

(define (run-program root program arguments)
  (let ((node (tool-name "NODE" "node")))
    (let ((status (system* (append (list node (path-join root "scripts/run-lofi.mjs") program) arguments))))
      status)))

(define (system* argv)
  (let ((record (run-command/capture argv '((include-output-hex? . #f)))))
    (display (option-ref record 'stdout ""))
    (display (option-ref record 'stderr "") (current-error-port))
    (option-ref record 'status 1)))

(define (report failure)
  (let ((port (current-error-port)))
    (if (error-object? failure)
        (begin (display (error-object-message failure) port)
               (for-each (lambda (irritant) (display " " port) (write irritant port)) (error-object-irritants failure)))
        (write failure port))
    (newline port)
    (exit 1)))

(let ((arguments (command-line)))
  (exit (guard (failure (#t (report failure)))
          (perform (cadr arguments) (request (cddr arguments))))))
