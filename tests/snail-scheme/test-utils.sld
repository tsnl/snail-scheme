(define-library (snail-scheme test-utils)
  (export
    expect
    run-test
    check-ok
    check-fail
    test-value
    at)

  (import
    (scheme base)
    (scheme write)
    (snail-scheme common)
    (snail-scheme source)
    (snail-scheme reader)
    (only (snail-scheme parser)
      parse-result-ok?
      parse-result-err?
      parse-result-value
      parse-result-input))

  (begin
    (define-syntax run-test
      (syntax-rules ()
        ((_ function-name)
          (begin
            (display-error "running test: ")
            (display-error `(,function-name))
            (display-error "\n")
            (function-name)))))

    (define (expect lhs rhs)
      (if (equal? lhs rhs)
        '()
        (begin
          (display-error (string-append (repeat-string "-" 80) "\n"))
          (display-error "expect failed\n")
          (display-error "lhs: ")
          (display-error lhs)
          (display-error "\n")
          (display-error "rhs: ")
          (display-error rhs)
          (display-error "\n")
          (display-error (string-append (repeat-string "-" 80) "\n"))
          (error "expect failed" lhs rhs))))

    ; Compare location fields explicitly instead of relying on record equality.
    (define (test-value value)
      (cond
        ((loc? value) (list (loc-filename value) (loc-line value) (loc-column value)))
        ((pair? value) (cons (test-value (car value)) (test-value (cdr value))))
        (else value)))

    (define (at line column)
      (make-loc "<anonymous-reader>" line column))

    ; Success defaults to consuming all input; failure defaults to consuming none.
    ; Supply a remainder to check prefix parsers and failures after partial progress.
    (define (check-ok parser text value . remainder)
      (let ((result (parser (string->reader text))))
        (expect
          (list text (parse-result-ok? result) (test-value (parse-result-value result))
            (list->string (reader-chars (parse-result-input result))))
          (list text #t (test-value value) (if (null? remainder) "" (car remainder))))))

    (define (check-fail parser text . remainder)
      (let ((result (parser (string->reader text))))
        (expect
          (list text (parse-result-err? result) (parse-result-value result)
            (list->string (reader-chars (parse-result-input result))))
          (list text #t '() (if (null? remainder) text (car remainder))))))))
