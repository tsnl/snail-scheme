(define-library (snail-scheme test-utils)
  (export expect run-test)
  (import
    (scheme base)
    (scheme write)
    (snail-scheme common))

  (begin

    (define-syntax run-test
      (syntax-rules ()
        ( (_ function-name)
          (begin
            (display-error "running test: ")
            (display-error `(,function-name))
            (display-error "\n")
            (function-name)) )))

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
    ))
