;; Compile source through located syntax and resolved IR directly to WasmGC.
;; Both Chibi and the native interpreter host this module. Build libraries own
;; external tools; this module only reads source and writes its Wasm output.
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

    (define-traced (source-file->wat-file root input output . options)
      (if (> (length options) 3) (error "expected foreign declarations, library directories, and CLI entry"))
      (let* ((foreign (if (null? options) '() (car options)))
             (directories (if (< (length options) 2) '() (cadr options)))
             (forms (source-file->syntax-list input))
             (core (make-core-library '(snail-scheme core) bootstrap-primitive-names))
             (extensions (make-extension-library (map car foreign)))
             (program (syntax-list->ir-library forms (library-loader root directories)
                                               (list core extensions))))
        (call-with-output-file output
          (lambda (port)
            (apply write-ir-library-as-wasm program (string-append root "/src/runtime/wasmgc.wat")
                   (string-append root "/src/runtime/awi.wat") port foreign
                   (if (= (length options) 3) (list (caddr options)) '()))))))

    ;; ---- Source and library loading ----

    (define-traced (source-file->syntax-list path)
      (reader->syntax-list (file->reader path)))

    (define (library-loader root directories)
      (lambda (name)
        (let* ((path (library-path root directories name))
               (forms (source-file->syntax-list path)))
          (if (not (= (length forms) 1))
              (error "expected exactly one library declaration" path))
          (car forms))))

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
