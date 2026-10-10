;; Join explicit representations: source files, located syntax, resolved HIR,
;; structured MIR, and LLVM text. The current Scheme host runs this module.
(define-library (snail-scheme compiler)
  (export source-file->llvm-file compiler-main)
  (import (scheme base) (scheme file)
          (snail-scheme trace) (snail-scheme bootstrap)
          (snail-scheme reader) (snail-scheme syntax-parser)
          (snail-scheme expand) (snail-scheme lower)
          (only (snail-scheme mir) write-mir-library) (snail-scheme llvm))
  (begin
    ;; ---- Compilation and output files ----

    (define (compiler-main arguments)
      (let ((operands (cdr arguments)))
        (if (or (not (memv (length operands) '(3 4))) (member "--timing" operands))
            (error "usage: compile.scm ROOT INPUT OUTPUT [MIR-DUMP]"))
        (apply source-file->llvm-file operands)))

    (define-traced (source-file->llvm-file root input output . optional-dump)
      (let* ((forms (source-file->syntax-list input))
             (core (make-core-library '(snail-scheme core) bootstrap-primitive-names))
             (hir (syntax-list->hir-library forms (library-loader root) (list core)))
             (program (hir-library->mir-library hir)))
        (mir-library->llvm-file program output)
        (if (pair? optional-dump)
            (mir-library->dump-file program (car optional-dump)))))

    (define-traced (mir-library->llvm-file program path)
      (call-with-output-file path (lambda (port) (write-mir-library-as-llvm program port))))

    (define-traced (mir-library->dump-file program path)
      (call-with-output-file path (lambda (port) (write-mir-library program port))))

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
