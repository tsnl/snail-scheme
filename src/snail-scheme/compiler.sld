;; The driver joins four explicit stages: located syntax, resolved HIR, stack
;; instructions, and LLVM text. The current Scheme host still runs this module.
(define-library (snail-scheme compiler)
  (export compile-file compiler-main)
  (import (scheme base) (scheme file) (scheme time) (scheme write)
          (snail-scheme bootstrap)
          (snail-scheme reader) (snail-scheme parser) (snail-scheme syntax-parser)
          (snail-scheme expand) (snail-scheme lower)
          (snail-scheme vm) (snail-scheme llvm))
  (begin
    ;; Optional diagnostics stay off program stdout and do not change artifacts.
    (define timing-port (make-parameter #f))

    (define (compiler-main arguments)
      (let ((operands (without-timing-flag (cdr arguments)))
            (report? (member "--timing" (cdr arguments))))
        (if (not (memv (length operands) '(3 4)))
            (error "usage: compile.scm ROOT INPUT OUTPUT [VM-DUMP] [--timing]"))
        (parameterize ((timing-port (and report? (current-error-port))))
          (apply compile-file operands))))

    (define (without-timing-flag arguments)
      (cond ((null? arguments) '())
            ((string=? (car arguments) "--timing") (without-timing-flag (cdr arguments)))
            (else (cons (car arguments) (without-timing-flag (cdr arguments))))))

    (define (compile-file root input output . optional-dump)
      (let* ((forms (time-stage 'parse (lambda () (read-source input))))
             (core (make-core-library '(snail-scheme core) bootstrap-primitive-names))
             (hir (time-stage 'expand
                              (lambda () (expand-program forms (library-loader root) (list core)))))
             (program (time-stage 'lower (lambda () (lower-program hir)))))
        (time-stage 'llvm (lambda () (write-program output program write-llvm-program)))
        (if (pair? optional-dump)
            (time-stage 'vm-dump
                        (lambda () (write-program (car optional-dump) program write-vm-program))))))

    (define (write-program path program writer)
      (call-with-output-file path (lambda (port) (writer program port))))

    (define (time-stage name thunk)
      (if (not (timing-port)) (thunk)
          (let* ((start (current-jiffy)) (result (thunk)))
            (report-timing name (- (current-jiffy) start))
            result)))

    (define (report-timing name ticks)
      (let ((port (timing-port)) (frequency (jiffies-per-second)))
        (display "compiler: " port) (display name port) (display " " port)
        (display (+ (* (quotient ticks frequency) 1000000)
                    (quotient (* (remainder ticks frequency) 1000000) frequency)) port)
        (display " us\n" port)))

    (define (read-source path)
      (let ((result (s-file (file->reader path))))
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
