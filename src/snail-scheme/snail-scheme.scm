(import
  (scheme base)
  (scheme write)
  (scheme process-context)
  (snail-scheme common)
  (snail-scheme parser)
  (snail-scheme test-utils))

;
; CLI args
;

(define-record-type <cli-args>
  (make-cli-args
    self-path     ; string
    input-path    ; string or null
    output-path)  ; string or null
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
  (let loop
    ( (argv argv)
      (wip-args (make-cli-args self '() '())) )
    (cond
      ( (null? argv)
        wip-args )

      ( (and
          (>= (length argv) 2)
          (equal? (first argv) "-o"))
        (loop
          (cddr argv)
          (cli-args-with-output-path wip-args (second argv))) )

      ( (and
          (>= (length argv) 1)
          (string? (first argv)))
        (loop
          (cdr argv)
          (cli-args-with-input-path wip-args (first argv))) )

      ( else
        (begin
          (display-error
            (string-append
              "Unrecognized args suffix: "
              (list->string argv)))
          (exit #f)) ))
    ))

(define (test-parse-cli-args)
  (expect
    (parse-cli-args "program" '("hello"))
    (make-cli-args "program" "hello" '()))
  (expect
    (parse-cli-args "program" '("hello" "-o" "output"))
    (make-cli-args "program" "hello" "output")))

;;; TODO: add tests for the error cases

;
; main
;

(define (main argv)
  (let*
    ( (args (parse-cli-args (car argv) (cdr argv)))
      )
    (begin
      (display-error args)
      (display-error "\n")
      (display-error "Hello, world\n"))))

;
; test
;

(define (test argv)
  ; main
  (run-test test-parse-cli-args)

  ; parser
  (run-test test-input-stream)
  (run-test test->>=)
  (run-test test-chain)
  (run-test test-char-if)
  (run-test test-repeat)
  (run-test test-discard)
  (run-test test-tuple)
  (run-test test-optional)
  (run-test test-tag)

  (display-error "All tests ok\n"))
