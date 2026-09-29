(define-library (snail-scheme test-cli)
  (export
   test-cli)

  (import
   (scheme base)
   (snail-scheme cli)
   (snail-scheme test-utils))

  (begin
    (define (test-parse-cli-args)
      (define (check argv expected)
        (let ((args (parse-cli-args "program" argv)))
          (expect (list (cli-args-self-path args) (cli-args-input-path args) (cli-args-output-path args))
                  expected)))
      (check '("hello") '("program" "hello" ()))
      (check '("hello" "-o" "output") '("program" "hello" "output")))

    ;; TODO: add tests for the error cases.

    (define (test-cli)
      (run-test test-parse-cli-args))))
