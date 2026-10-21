;; The lofi command: compile, run, or print the WebAssembly text of a program;
;; or build a Scheme kernel and talk to it in a REPL or a notebook.
(import
 (scheme base)
 (scheme file)
 (scheme process-context)
 (scheme write)
 (chibi filesystem)
 (chibi pathname)
 (chibi process)
 (lofi build))

;; ---- Requests ----

(define usage
  "usage: lofi compile|run|wat|schema [--release] [-I DIR] [-o OUTPUT] SOURCE [ARGUMENT ...] | lofi repl|notebook [--release] [-I DIR] [-o OUTPUT] [KERNEL] | lofi bootstrap")

(define (absolute path)
  (if (path-absolute? path) path (path-join (current-directory) path)))

;; The REPL and the notebook take a kernel program, by default the notebook's
;; own.
(define (kernel-action? action)
  (member action '("repl" "notebook")))

;; Returns an association list of the options, the source and its arguments.
(define (request root arguments)
  (unless (and (pair? arguments) (member (car arguments) '("compile" "run" "wat" "schema" "repl" "notebook"))) (error usage))
  (let loop ((rest (cdr arguments)) (options (list (cons 'action (car arguments)))))
    (cond ((null? rest)
           (unless (kernel-action? (car arguments)) (error usage))
           (append options (list (cons 'source (path-join root "src/notebook/kernel.sld")) (cons 'arguments '()))))
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
    (cond
     ((string=? action "wat") (write-string (program->wat root (directories root options) source)) 0)
     ((string=? action "schema") (write-string (program->schemas root (directories root options) source)) 0)
     ((string=? action "repl") (run-repl root (directories root options) source (option options 'release #f)))
     ((string=? action "notebook")
      (package-notebook root (directories root options) source (option options 'output (path-join root "build/notebook"))
                        (option options 'release #f)))
     (else
      (let ((output (or (option options 'output #f) (path-join root "build/lofi-run/program.wasm"))))
        (build-program root (directories root options) source output (option options 'release #f))
        (if (string=? action "compile")
            0
            (run-program root output (option options 'arguments '()))))))))

;; The program inherits standard input and output; its status is returned.
(define (run-program root program arguments)
  (let ((status (cadr (apply system (or (get-environment-variable "NODE") "node") "--no-warnings"
                             (path-join root "scripts/run-lofi.mjs") program arguments))))
    (quotient status 256)))

;; ---- Kernels ----

;; The REPL runs in Node, like a program, and keeps the terminal.
(define (run-repl root directories kernel release?)
  (let ((program (path-join root "build/lofi-repl/kernel.wasm")))
    (build-program root directories kernel program release?)
    (quotient (cadr (system (or (get-environment-variable "NODE") "node") "--no-warnings" (path-join root "scripts/repl.mjs") program))
              256)))

;; The notebook is a static site: the kernel beside the page and its
;; scripts. Modules and Wasm do not load from file: URLs, so it is served.
(define notebook-files
  '("index.html" "notebook.mjs" "notebook.css" "kernel.mjs" "worker.mjs"))

(define (package-notebook root directories kernel output release?)
  (let ((intermediate (path-join root "build/notebook-intermediates/kernel.wasm")))
    (build-program root directories kernel intermediate release?)
    (create-directory* output)
    (copy-file! intermediate (path-join output "kernel.wasm"))
    (for-each (lambda (file) (copy-file! (path-join root "src/notebook" file) (path-join output file))) notebook-files)
    (display (string-append "The notebook is in " output "; serve it, as with
  python3 -m http.server --directory " output "
"))
    0))

(define (copy-file! from to)
  (let ((bytes (call-with-port (open-binary-input-file from) (lambda (port) (read-bytevector (file-size from) port)))))
    (call-with-port (open-binary-output-file to) (lambda (port) (write-bytevector bytes port)))))

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
          (if (equal? (cddr arguments) '("bootstrap"))
              (begin (bootstrap! (cadr arguments)) 0)
              (perform (cadr arguments) (request (cadr arguments) (cddr arguments)))))))
