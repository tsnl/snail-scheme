;; Compile source through located syntax and resolved IR directly to WasmGC.
;; The current Chibi host runs this module; Wasm tools assemble and link its output.
(define-library (snail-scheme compiler)
  (export source-file->wasm-file compiler-main)
  (import (scheme base) (scheme cxr) (scheme file) (scheme write)
          (snail-scheme trace) (snail-scheme bootstrap)
          (snail-scheme reader) (snail-scheme syntax-parser)
          (snail-scheme expand) (snail-scheme wasm)
          (snail-scheme syntax)
          (only (snail-scheme ir) make-value-definition value-definition?)
          (snail-scheme library))
  (begin
    ;; ---- Compilation and output files ----

    (define (compiler-main arguments)
      (let* ((actor? (and (pair? (cdr arguments)) (string=? (cadr arguments) "--actor")))
             (operands (if actor? (cddr arguments) (cdr arguments))))
        (if (or (< (length operands) 3) (not (= (modulo (- (length operands) 3) 2) 0)))
            (error "usage: compile.scm [--actor] ROOT INPUT OUTPUT.wat [WASM-MODULE SCHEME-NAME] ..."))
        (source-file->wasm-file (car operands) (cadr operands) (caddr operands)
                                (foreign-declarations (cdddr operands)) actor?)))

    (define (foreign-declarations arguments)
      (if (null? arguments) '()
          (cons (cons (string->symbol (cadr arguments)) (car arguments))
                (foreign-declarations (cddr arguments)))))

    (define (make-extension-library names)
      (make-library '(snail-scheme extensions) '()
                    (map (lambda (name) (make-named-binding name (make-value-definition name #f))) names)
                    '() '() #f))

    (define-traced (source-file->wasm-file root input output . options)
      (let* ((foreign (if (null? options) '() (car options)))
             (forms (source-file->syntax-list input))
             (core (make-core-library '(snail-scheme core) bootstrap-primitive-names))
             (extensions (make-extension-library (map car foreign)))
             (actor? (and (pair? options) (pair? (cdr options)) (cadr options)))
             (program (if actor?
                          (actor-library forms (library-loader root) (list core extensions))
                          (syntax-list->ir-library forms (library-loader root) (list core extensions)))))
        (call-with-output-file output
          (lambda (port)
            (write-ir-library-as-wasm program (string-append root "/runtime/wasmgc.wat")
                                      (string-append root "/runtime/awi.wat") port foreign)))))

    ;; ---- Actor library facade ----

    ;; Load the user's library and the codec in one expansion cache. The facade
    ;; has no executable body: its resolved exports retain the original bindings.
    ;; Prefixes separate codec operations from user methods without reserving names
    ;; inside the user's library. Macro exports never become runtime methods.
    (define (actor-library forms loader initial)
      (if (not (= (length forms) 1)) (error "--actor expects one define-library"))
      (let* ((form (car forms)) (name (actor-library-name form))
             (source (actor-imports name))
             (facade (syntax-list->ir-library
                      source (lambda (requested) (if (equal? requested name) form (loader requested)))
                      initial)))
        (make-library #f (library-imports facade) (actor-exports facade)
                      (library-dependencies facade) '() (library-loc facade))))

    (define (actor-library-name form)
      (let ((datum (syntax->datum form)))
        (if (not (and (pair? datum) (eq? (car datum) 'define-library)
                      (pair? (cdr datum)) (list? (cadr datum)) (pair? (cadr datum))))
            (error "--actor expects one define-library"))
        (if (equal? (cadr datum) '(snail-scheme actor-wire))
            (error "the actor codec cannot be its own entry library"))
        (cadr datum)))

    (define (actor-imports name)
      (let ((port (open-output-string)))
        (write `(import (prefix ,name method:)
                        (prefix (snail-scheme actor-wire) wire:)) port)
        (reader->syntax-list (string->reader "<actor imports>" (get-output-string port)))))

    (define (actor-exports facade)
      (let loop ((bindings (import-declaration-bindings (car (library-imports facade)))))
        (cond ((null? bindings) '())
              ((value-definition? (named-binding-definition (car bindings)))
               (cons (car bindings) (loop (cdr bindings))))
              (else (loop (cdr bindings))))))

    ;; ---- Source and library loading ----

    (define-traced (source-file->syntax-list path)
      (reader->syntax-list (file->reader path)))

    (define (library-loader root)
      (lambda (name)
        (let* ((path (library-path root name))
               (forms (source-file->syntax-list path)))
          (if (not (= (length forms) 1))
              (error "expected exactly one library declaration" path))
          (car forms))))

    (define (library-path root name)
      (string-append root "/" (if (eq? (car name) 'scheme) "bootstrap/" "src/")
                     (library-name-path name) ".sld"))

    (define (library-name-path name)
      (let ((first (if (symbol? (car name)) (symbol->string (car name))
                       (number->string (car name)))))
        (if (null? (cdr name)) first
            (string-append first "/" (library-name-path (cdr name))))))))
