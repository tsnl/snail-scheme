;; Read an application's option prefix without applying application policy.
;; Declarations map literal names to #t (one string operand) or #f (a switch).
(define-library (snail-scheme options)
  (export parse-options)
  (import (scheme base))
  (begin

    ;; ---- Option spelling ----

    ;; #f means no attached operand; an empty string is still an operand.
    ;; Long names split at the first =; short names occupy two characters.
    (define (split-long-option argument)
      (let ((end (string-length argument)))
        (let search ((index 2))
          (cond ((= index end) (values argument #f))
                ((char=? (string-ref argument index) #\=)
                 (values (substring argument 0 index) (substring argument (+ index 1) end)))
                (else (search (+ index 1)))))))

    (define (split-option argument)
      (let ((end (string-length argument)))
        (cond ((and (> end 2) (char=? (string-ref argument 1) #\-))
               (split-long-option argument))
              ((> end 2) (values (substring argument 0 2) (substring argument 2 end)))
              (else (values argument #f)))))

    ;; ---- Declared options and operands ----

    ;; Consume exactly one option occurrence. Separate operands stay literal,
    ;; including empty strings, --, and strings that look like other options.
    (define (consume-option declarations arguments usage)
      (let-values (((name attached) (split-option (car arguments))))
        (let ((declaration (assoc name declarations)) (remaining (cdr arguments)))
          (cond ((not declaration) (apply error "unknown option" (car arguments) usage))
                ((not (cdr declaration))
                 (if attached (apply error "option does not take an argument" name usage))
                 (values (cons name #t) remaining))
                (attached (values (cons name attached) remaining))
                ((null? remaining) (apply error "option requires an argument" name usage))
                (else (values (cons name (car remaining)) (cdr remaining)))))))

    ;; ---- The option prefix and positional suffix ----

    ;; Input excludes the executable name. Return occurrences in input order
    ;; and the original remaining list tail. -- is consumed; the first positional
    ;; string and all following strings remain untouched. The caller owns aliases,
    ;; repetition, conversion, required positionals, and optional usage text.
    (define (parse-options declarations arguments . usage)
      (if (> (length usage) 1) (error "expected at most one usage string"))
      (let scan ((remaining arguments) (reversed '()))
        (cond ((null? remaining) (values (reverse reversed) remaining))
              ((string=? (car remaining) "--") (values (reverse reversed) (cdr remaining)))
              ((and (> (string-length (car remaining)) 0)
                    (char=? (string-ref (car remaining) 0) #\-))
               (let-values (((option rest) (consume-option declarations remaining usage)))
                 (scan rest (cons option reversed))))
              (else (values (reverse reversed) remaining))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (import (snail-scheme test-utils))
    (export test-options)
    (begin
      (define test-declarations
        '(("-I" . #t) ("-o" . #t) ("--output" . #t) ("-v" . #f) ("--verbose" . #f)))

      (define (parsed arguments)
        (call-with-values (lambda () (parse-options test-declarations arguments)) list))

      (define (parse-error arguments)
        (guard (failure (else (list (error-object-message failure) (error-object-irritants failure))))
          (parse-options test-declarations arguments "usage: sample")))

      (define (test-option-spelling)
        (expect (parsed '("-Isrc" "-o" "out" "--output=a=b" "-v" "--verbose"))
                '((("-I" . "src") ("-o" . "out") ("--output" . "a=b")
                   ("-v" . #t) ("--verbose" . #t)) ()))
        (expect (parsed '("-I=src" "--output" "space in value"))
                '((("-I" . "=src") ("--output" . "space in value")) ()))
        (expect (parsed '("-I" "" "--output=")) '((("-I" . "") ("--output" . "")) ())))

      (define (test-option-boundaries)
        (expect (parsed '()) '(() ()))
        (expect (parsed '("" "-v")) '(() ("" "-v")))
        (expect (parsed '("--" "-v" "")) '(() ("-v" "")))
        (expect (parsed '("-I" "--" "-v" "file")) '((("-I" . "--") ("-v" . #t)) ("file")))
        (expect (parsed '("-I" "-v" "file")) '((("-I" . "-v")) ("file")))
        (let* ((suffix '("script.scm" "-Ithird" "--" ""))
               (arguments (cons "-Ifirst" (cons "-Isecond" suffix))))
          (let-values (((options remaining) (parse-options test-declarations arguments)))
            (expect options '(("-I" . "first") ("-I" . "second")))
            (expect (eq? remaining suffix) #t)
            (expect arguments '("-Ifirst" "-Isecond" "script.scm" "-Ithird" "--" "")))))

      (define (test-option-errors)
        (expect (parse-error '("-I")) '("option requires an argument" ("-I" "usage: sample")))
        (expect (parse-error '("--output"))
                '("option requires an argument" ("--output" "usage: sample")))
        (expect (parse-error '("-vfoo")) '("option does not take an argument" ("-v" "usage: sample")))
        (expect (parse-error '("--verbose="))
                '("option does not take an argument" ("--verbose" "usage: sample")))
        (expect (parse-error '("--output-more=x"))
                '("unknown option" ("--output-more=x" "usage: sample")))
        (expect (parse-error '("-x")) '("unknown option" ("-x" "usage: sample")))
        (expect (parse-error '("-")) '("unknown option" ("-" "usage: sample"))))

      (define (test-options)
        (run-test test-option-spelling)
        (run-test test-option-boundaries)
        (run-test test-option-errors))))
   (else)))
