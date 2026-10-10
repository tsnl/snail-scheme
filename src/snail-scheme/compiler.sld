;; Compile source through located syntax and resolved IR directly to WasmGC.
;; The current Chibi host runs this module; Wasm tools assemble and link its output.
(define-library (snail-scheme compiler)
  (export source-file->wat-file)
  (import (scheme base) (scheme cxr) (scheme file)
          (snail-scheme trace) (snail-scheme bootstrap)
          (snail-scheme reader) (snail-scheme syntax-parser)
          (snail-scheme expand) (snail-scheme wasm)
          (only (snail-scheme ir) make-value-definition)
          (only (snail-scheme library) make-library make-named-binding))
  (begin
    ;; ---- Compilation and output files ----

    (define (make-extension-library names)
      (make-library '(snail-scheme extensions) '()
                    (map (lambda (name) (make-named-binding name (make-value-definition name #f))) names)
                    '() '() #f))

    (define-traced (source-file->wat-file root input output . optional-foreign)
      (let* ((foreign (if (null? optional-foreign) '() (car optional-foreign)))
             (forms (source-file->syntax-list input))
             (core (make-core-library '(snail-scheme core) bootstrap-primitive-names))
             (extensions (make-extension-library (map car foreign)))
             (program (syntax-list->ir-library forms (library-loader root) (list core extensions))))
        (call-with-output-file output
          (lambda (port)
            (write-ir-library-as-wasm program (string-append root "/src/runtime/wasmgc.wat")
                                      (string-append root "/src/runtime/awi.wat") port foreign)))))

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
