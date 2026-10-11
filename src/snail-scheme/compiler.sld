;; Portable source compilation: library loading, expansion, and Wasm datums.
;; A build driver can supply a generator resolver without importing host effects.
(define-library (snail-scheme compiler)
  (export source-file->wasm source-file->wat-file syntax-list->wasm
          library-generator read-library-form)
  (import (scheme base) (scheme cxr) (scheme file)
          (snail-scheme chromium-trace) (snail-scheme bootstrap)
          (snail-scheme reader) (snail-scheme syntax-parser)
          (snail-scheme expand) (snail-scheme wasm) (snail-scheme syntax)
          (only (snail-scheme ir) make-value-definition)
          (only (snail-scheme library) make-library make-named-binding))
  (begin

    ;; ---- Portable compilation ----

    (define source-file->wat-file
      (chromium-trace
       "source-file->wat-file"
       (lambda (root input output . options)
         (let ((datum (apply source-file->wasm root input options)))
           (call-with-output-file output (lambda (port) (write-wasm datum port)))))))

    (define source-file->wasm
      (chromium-trace
       "source-file->wasm"
       (lambda (root input . options)
         (when (> (length options) 3) (error "expected foreign declarations, library directories, and CLI entry"))
         (syntax-list->wasm root (source-file->syntax-list input)
                            (if (null? options) '() (car options))
                            (if (< (length options) 2) '() (cadr options))
                            (if (= (length options) 3) (caddr options) #f)))))

    (define (make-extension-library names)
      (make-library '(snail-scheme extensions) '()
                    (map (lambda (name) (make-named-binding name (make-value-definition name #f))) names)
                    '() '() #f))

    (define (syntax-list->wasm root forms foreign directories entry)
      (let* ((core (make-core-library '(snail-scheme core) bootstrap-primitive-names))
             (extensions (make-extension-library (map car foreign)))
             (program (syntax-list->ir-library forms (library-loader root directories) (list core extensions))))
        (ir-library->wasm program foreign entry)))

    ;; ---- Library loading and the build-stage boundary ----

    ;; The callback returns an ordinary located define-library form. The portable
    ;; default reports the missing capability at the wrapper, before any effects.
    (define library-generator
      (make-parameter (lambda (root path wrapper directories)
                        (error "generate-library requires a build compilation" path))))

    (define source-file->syntax-list
      (chromium-trace "source-file->syntax-list"
                      (lambda (path) (reader->syntax-list (file->reader path)))))

    (define (read-library-form path)
      (let ((forms (source-file->syntax-list path)))
        (unless (= (length forms) 1) (error "expected exactly one library declaration" path))
        (car forms)))

    (define (generated-form? form)
      (and (list-syntax? form) (pair? (list-syntax-elements form))
           (eq? (syntax->datum (car (list-syntax-elements form))) 'generate-library)))

    (define (library-loader root directories)
      (lambda (name)
        (let* ((path (library-path root directories name)) (form (read-library-form path)))
          (if (not (generated-form? form)) form
              (begin
                (unless (and (>= (length (list-syntax-elements form)) 2)
                             (equal? (syntax->datum (cadr (list-syntax-elements form))) name))
                  (error "library name does not match import" path name))
                ((library-generator) root path form directories))))))

    ;; Standard libraries belong to the bootstrap runtime. Project directories
    ;; precede the compiler's own sources for every other library name.
    (define (library-path root directories name)
      (let* ((roots (if (eq? (car name) 'scheme) (list (string-append root "/bootstrap"))
                        (append directories (list (string-append root "/src")))))
             (paths (map (lambda (directory)
                           (string-append directory "/" (library-name-path name) ".sld")) roots)))
        (let search ((remaining paths))
          (cond ((null? remaining) (error "library not found; searched paths" name paths))
                ((file-exists? (car remaining)) (car remaining))
                (else (search (cdr remaining)))))))

    (define (library-name-path name)
      (let ((first (if (symbol? (car name)) (symbol->string (car name))
                       (number->string (car name)))))
        (if (null? (cdr name)) first
            (string-append first "/" (library-name-path (cdr name))))))))
