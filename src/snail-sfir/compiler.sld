;; Map compilation resolves supplied library values before checking. The source
;; driver alone reads files and assembles dependencies. Later stages refine IR.
(define-library (snail-sfir compiler)
  (export library-directories command-program? library-map->core
          source-file->core source-file->wasm source-file->wat-file)
  (import (scheme base) (scheme file) (scheme write)
          (snail-scheme reader) (snail-scheme syntax-parser) (snail-sfir frontend) (snail-sfir library)
          (snail-scheme strict-infer) (snail-scheme strict-primitives)
          (snail-scheme strict-specialize) (snail-scheme strict-wasm)
          (snail-scheme chromium-trace)
          (only (snail-scheme strict-types) strict-error resolve)
          (only (snail-scheme strict-core) program-body)
          (only (snail-scheme ir) node-type node-loc binding-kind binding-payload)
          (only (snail-scheme source) loc?)
          (only (snail-scheme wasm) write-wasm)
          (prefix (snail-scheme library) library:))
  (begin

    ;; ---- Source and module loading ----

    (define library-directories (make-parameter '()))
    (define (read-forms path) (reader->syntax-list (file->reader path)))
    (define (library-path directory name)
      (let join ((parts name) (path directory))
        (if (null? parts) (string-append path ".sfir")
            (join (cdr parts) (string-append path "/" (symbol->string (car parts)))))))
    (define (library-loader root)
      (lambda (name)
        (let search ((directories (append (library-directories) (list (string-append root "/lib")))))
          (and (pair? directories)
               (let ((path (library-path (car directories) name)))
                 (if (file-exists? path)
                     (let ((forms (read-forms path)))
                       (unless (= (length forms) 1) (error "expected one SFIR library declaration" path name))
                       (car forms))
                     (search (cdr directories))))))))
    (define (primitive-bindings libraries)
      (let ((bindings '()))
        (for-each (lambda (library)
                    (for-each (lambda (entry)
                                (let ((binding (library:named-binding-definition entry)))
                                  (when (and (eq? (binding-kind binding) 'primitive) (not (assq binding bindings)))
                                    (set! bindings (cons (cons binding (binding-payload binding)) bindings)))))
                              (library:library-exports library))) libraries)
        bindings))
    (define (raise-source-diagnostic failure)
      (let ((details (and (error-object? failure) (error-object-irritants failure))))
        (if (and (pair? details) (loc? (car details)))
            (apply strict-error (car details) (error-object-message failure) (cdr details))
            (raise failure))))
    (define (source-file->core root path)
      (guard (failure (else (raise-source-diagnostic failure)))
        (let* ((source ((chromium-trace "sfir.parse" syntax-list->sfir-library) (read-forms path)))
               (libraries (collect-library-map source (library-loader root)
                                               (list (cons '(sfir primitive) (make-primitive-library primitive-names)))))
               (program ((chromium-trace "sfir.resolve" resolve-source-library) source libraries '())))
          ((chromium-trace "sfir.infer" resolved-library->core) program))))

    ;; ---- Compilation from supplied library values ----

    (define (library-map->core libraries root-key)
      (guard (failure (else (raise-source-diagnostic failure)))
        (let* ((resolved (resolve-library-map libraries))
               (root (assoc root-key resolved)))
          (unless root (error "SFIR root library not found" root-key))
          (resolved-library->core (cdr root)))))
    (define (resolved-library->core program)
      (let* ((libraries (library:library-dependency-order program))
             (items (apply append (map library:library-body libraries))))
        (infer-program items (primitive-bindings libraries) (library:library-loc program))))

    ;; ---- Concrete specialization and Wasm emission ----

    (define command-program? (make-parameter #f))
    (define (check-command-result core)
      (let ((body (program-body core)))
        (when (and (command-program?) (not (memq (resolve (node-type body)) '(Unit I32 I64 Never))))
          (strict-error (node-loc body) "command result must be Unit, I32, I64 or Never" (node-type body)))))
    (define (source-file->wasm root path . exports)
      (let ((core (source-file->core root path)))
        (check-command-result core)
        (let ((concrete (apply (chromium-trace "sfir.specialize" monomorphize) core exports)))
          ((chromium-trace "sfir.emit-wasm" strict-core->wasm) concrete))))
    (define (source-file->wat-file root path output . exports)
      (let ((module (apply source-file->wasm root path exports)))
        (call-with-output-file output (lambda (port) (write-wasm module port))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-compiler)
    (import (snail-scheme test-utils)
            (only (chibi temp-file) call-with-temp-dir)
            (only (snail-scheme ir) name-definition application-operator lambda-body value-binding-initializer))
    (begin
      (define (test-parsed text)
        (call-with-temp-dir
         "sfir-map-source"
         (lambda (directory preserve)
           (with-chromium-trace-to
            (string-append directory "/parse.json")
            (lambda () (parse-library (car (reader->syntax-list (string->reader "map-compilation.sfir" text)))))))))
      (define (test-map-compilation)
        (let* ((primitive (make-primitive-library primitive-names))
               (provider (test-parsed "(define-library (test math)
                                       (import (only (sfir primitive) i32-add)) (export increment)
                                       (begin (def increment (lambda (x) (i32-add x 1)))))"))
               (app (test-parsed "(define-library (test app) (import (test math))
                                  (begin (increment 41)))"))
               (libraries (list (cons '(sfir primitive) primitive) (cons '(test math) provider)
                                (cons '(test app) app))))
          (expect (resolve (node-type (program-body (library-map->core libraries '(test app))))) 'I32)
          (expect (resolve (node-type (program-body (library-map->core libraries '(test app))))) 'I32)
          (expect (scoped-reference?
                   (name-definition (application-operator
                                     (lambda-body (value-binding-initializer
                                                   (car (sfir-library-declarations provider))))))) #t)))
      (define (test-compiler)
        (run-test test-map-compilation))))
   (else)))
