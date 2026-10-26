;; The lofi command: compile, run, or print the WebAssembly text of a program.
(import
 (scheme base)
 (scheme cxr)
 (scheme process-context)
 (chibi process)
 (lofi build)
 (lofi project-build))

;; ---- Requests ----

(define usage "usage: lofi compile|run|wat|schema [--release] [-I DIR] [-o OUTPUT] SOURCE [ARGUMENT ...] | lofi bootstrap")

;; Returns an association list of the options, the source and its arguments.
(define (request arguments)
  (unless (and (pair? arguments) (member (car arguments) '("compile" "run" "wat" "schema"))) (error usage))
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

(define (perform-project-build root arguments)
  (let* ((release? (and (pair? arguments) (string=? (car arguments) "--release")))
         (paths (if release? (cdr arguments) arguments)))
    (unless (= (length paths) 2) (error "usage: lofi build [--release] PROJECT TARGET"))
    (write-string (build-project root (absolute (car paths)) (cadr paths) release?))
    (newline)
    0))

(define (perform root options)
  (let ((source (option options 'source #f)) (action (option options 'action "run")))
    (cond
     ((string=? action "wat") (write-string (program->wat root (directories root options) source)) 0)
     ((string=? action "schema") (write-string (program->schemas root (directories root options) source)) 0)
     ((option options 'output #f)
      => (lambda (output)
           (run-if-requested root options (build-program-directory root (directories root options) source output (option options 'release #f)))))
     ((string=? action "compile") (error "lofi compile requires -o DIRECTORY"))
     ;; Without -o the program lives as long as its run, in a directory of
     ;; its own, so runs at once in one checkout never share a file.
     (else (with-private-directory root
                                   (lambda (directory)
                                     (run-if-requested root options (build-program root (directories root options) source (path-join directory "program.wasm")
                                                                                   (option options 'release #f)))))))))

(define (run-if-requested root options program)
  (if (string=? (option options 'action "run") "compile")
      0
      (run-program root program (option options 'arguments '()))))

;; The program inherits standard input and output; its status is returned.
(define (run-program root program arguments)
  (let ((status (cadr (apply system (append (node-command root program) arguments)))))
    (quotient status 256)))

;; The tools the development server runs, built if needed, as JSON for
;; scripts/develop.mjs.
(define (print-tools root)
  (write-string "{")
  (let loop ((tools (build-tools root)) (first? #t))
    (unless (null? tools)
      (write-string (string-append (if first? "" ", ") "\"" (caar tools) "\": \"" (cdar tools) "\""))
      (loop (cdr tools) #f)))
  (write-string "}\n")
  0)

(let ((arguments (command-line)))
  (exit (guard (failure (#t (report-failure "lofi" failure)))
          (cond ((equal? (cddr arguments) '("bootstrap")) (bootstrap! (cadr arguments)) 0)
                ((equal? (cddr arguments) '("tools")) (print-tools (cadr arguments)))
                ((and (pair? (cddr arguments)) (string=? (caddr arguments) "build")) (perform-project-build (cadr arguments) (cdddr arguments)))
                (else (perform (cadr arguments) (request (cddr arguments))))))))
