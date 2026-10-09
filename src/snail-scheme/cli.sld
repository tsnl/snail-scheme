(define-library (snail-scheme cli)
  (export
   parse-cli-args
   cli-args?
   cli-args-self-path
   cli-args-input-path
   cli-args-output-path)

  (import
   (scheme base)
   (scheme process-context)
   (snail-scheme common))

  (begin
    (define-record-type <cli-args>
      (make-cli-args
       self-path ; string
       input-path ; string or null
       output-path) ; string or null
      cli-args?
      (self-path cli-args-self-path)
      (input-path cli-args-input-path)
      (output-path cli-args-output-path))

    (define (cli-args-with-input-path wip-args input-path)
      (make-cli-args
       (cli-args-self-path wip-args)
       input-path
       (cli-args-output-path wip-args)))

    (define (cli-args-with-output-path wip-args output-path)
      (make-cli-args
       (cli-args-self-path wip-args)
       (cli-args-input-path wip-args)
       output-path))

    (define (parse-cli-args self argv)
      (let loop ((argv argv)
                 (wip-args (make-cli-args self '() '())))
        (cond
         ((null? argv)
          wip-args)

         ((and
           (>= (length argv) 2)
           (equal? (first argv) "-o"))
          (loop
           (cddr argv)
           (cli-args-with-output-path wip-args (second argv))))

         ((and
           (>= (length argv) 1)
           (string? (first argv)))
          (loop
           (cdr argv)
           (cli-args-with-input-path wip-args (first argv))))

         (else
          (begin
            (display-error
             (string-append
              "Unrecognized args suffix: "
              (list->string argv)))
            (exit #f)))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-cli)
    (import (snail-scheme test-utils))
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
        (run-test test-parse-cli-args))
      ))))
