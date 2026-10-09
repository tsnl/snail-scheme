;; The driver joins four explicit stages: located syntax, resolved HIR, stack
;; instructions, and LLVM text. The current Scheme host still runs this module.
(define-library (snail-scheme compiler)
  (export compile-file compiler-main)
  (import (scheme base) (scheme file)
          (snail-scheme bootstrap)
          (snail-scheme reader) (snail-scheme parser) (snail-scheme syntax-parser)
          (snail-scheme expand) (snail-scheme lower)
          (snail-scheme vm) (snail-scheme llvm))
  (begin
    (define (compiler-main arguments)
      (let ((operands (cdr arguments)))
        (if (not (memv (length operands) '(3 4)))
            (error "usage: compile.scm ROOT INPUT OUTPUT [VM-DUMP]"))
        (apply compile-file operands)))

    (define (compile-file root input output . optional-dump)
      (let* ((forms (read-source input))
             (core (make-core-library '(snail-scheme core) bootstrap-primitive-names))
             (hir (expand-program forms (library-loader root) (list core)))
             (program (lower-program hir)))
        (call-with-output-file output (lambda (port) (write-llvm-program program port)))
        (if (pair? optional-dump)
            (call-with-output-file (car optional-dump)
              (lambda (port) (write-vm-program program port))))))

    (define (read-source path)
      (let ((result ((s-file) (file->reader path))))
        (if (parse-result-err? result)
            (error "cannot parse Scheme source" path (reader-loc (parse-result-input result))))
        (parse-result-value result)))

    (define (library-loader root)
      (lambda (name)
        (let* ((path (library-path root name))
               (forms (read-source path)))
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
