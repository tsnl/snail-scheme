;; Assertions shared by the compiler's unit tests.
(define-library (snail-core testing)
  (export
   expect)
  (import
   (scheme base)
   (scheme write))
  (begin

    (define (expect actual expected)
      (unless (equal? actual expected)
        (let ((port (current-error-port)))
          (display "expected: " port) (write expected port) (newline port)
          (display "actual:   " port) (write actual port) (newline port)
          (error "unit test failed" actual expected))))

    ))
