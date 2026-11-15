;; Internal compiler commands: source execution, inspection and bootstrap.
(import
 (chezscheme)
 (snail stage0 system)
 (snail stage0 build))

;; ---- Requests ----

(define usage
  "usage: scripts/snail-tool compile|run|wat|schema [--error-format=text|json] [--release] [-I DIR] [-o OUTPUT] SOURCE [ARGUMENT ...] | scripts/snail-tool bootstrap")

;; Returns an association list of the options, the source and its arguments.
(define (request arguments)
  (unless (and (pair? arguments) (member (car arguments) '("compile" "run" "wat" "schema")))
    (error 'snail usage))
  (let loop ((rest (cdr arguments)) (options (list (cons 'action (car arguments)))))
    (cond ((null? rest) (error 'snail usage))
          ((string=? (car rest) "--release") (loop (cdr rest) options))
          ((member (car rest) '("--error-format=text" "--error-format=json"))
           (compiler-error-format (substring (car rest) 15 (string-length (car rest))))
           (loop (cdr rest) options))
          ((member (car rest) '("-I" "-o"))
           (when (null? (cdr rest)) (error 'snail usage))
           (loop (cddr rest)
                 (cons
                  (cons (if (string=? (car rest) "-I") 'library 'output) (absolute (cadr rest)))
                  options)))
          ((and (> (string-length (car rest)) 0) (char=? (string-ref (car rest) 0) #\-))
           (error 'snail (string-append "unknown option " (car rest))))
          (else (append options
                        (list (cons 'source (absolute (car rest)))
                              (cons 'arguments (cdr rest))))))))

(define (option options name default)
  (let ((entry (assq name options))) (if entry (cdr entry) default)))

(define (directories root options)
  (append (reverse (map cdr (filter-library options))) (standard-directories root)))

(define (filter-library options)
  (let loop ((options options) (out '()))
    (cond ((null? options) out)
          ((eq? (caar options) 'library) (loop (cdr options) (cons (car options) out)))
          (else (loop (cdr options) out)))))

;; ---- Actions ----

(define (perform root options)
  (let ((source (option options 'source #f)) (action (option options 'action "run")))
    (cond
     ((string=? action "wat")
      (write-string (program->wat root (directories root options) source))
      0)
     ((string=? action "schema")
      (write-string (program->schemas root (directories root options) source))
      0)
     ((option options 'output #f)
      => (lambda (output)
           (run-if-requested root
                             options
                             (build-program root
                                            (directories root options)
                                            source
                                            output
                                            (build-runtime root #f)))))
     ((string=? action "compile") (error 'snail "source compilation requires -o FILE"))
     ;; Without -o the program lives as long as its run, in a directory of
     ;; its own, so runs at once in one checkout never share a file.
     (else (with-private-directory root
                                   (lambda (directory)
                                     (run-if-requested root
                                                       options
                                                       (build-program root
                                                                      (directories root options)
                                                                      source
                                                                      (path-join directory
                                                                                 "program.wasm")
                                                                      (build-runtime root
                                                                                     #f)))))))))

(define (run-if-requested root options program)
  (if (string=? (option options 'action "run") "compile")
      0
      (run-program root program (option options 'arguments '()))))

;; The program inherits standard input and output; its status is returned.
(define (run-program root program arguments)
  (let ((status (run-command-status (append (program-command root program) arguments))))
    (quotient status 256)))

;; Tools in the order their shell launcher consumes them, one path a line.
(define (print-paths tools)
  (for-each (lambda (tool) (write-string tool) (newline)) tools)
  0)

(let ((arguments (command-line)))
  (exit (guard (failure (#t (report-failure failure)))
          (cond ((equal? (cddr arguments) '("bootstrap")) (bootstrap! (cadr arguments)) 0)
                ((equal? (cddr arguments) '("cli-tools"))
                 (print-paths (build-cli-tools (cadr arguments))))
                ((equal? (cddr arguments) '("dev-tools"))
                 (print-paths (build-editor-tools (cadr arguments))))
                ((equal? (cddr arguments) '("book-tools"))
                 (print-paths (build-book-tools (cadr arguments))))
                ((equal? (cddr arguments) '("format-tools"))
                 (print-paths (build-format-tools (cadr arguments))))
                (else (perform (cadr arguments) (request (cddr arguments))))))))
