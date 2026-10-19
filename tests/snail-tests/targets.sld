;; Exact independent answers are shared by raw and optimized Wasm.
(define-library (snail-tests targets)
  (export run-target-suite numeric-corpus)
  (import
   (scheme base)
   (scheme cxr)
   (scheme char)
   (scheme inexact)
   (scheme write)
   (srfi 1)
   (only (chibi string) string-split string-prefix? string-suffix?)
   (chibi regexp)
   (chibi regexp pcre)
   (snail-tests harness))
  (begin

    ;; ---- Complete decimal strings and binary64 observations ----

    (define (numeric-corpus suite domain?)
      (let* ((cases (rows (read-json (fixture suite (if domain? "domain.json" "cases.json")))))
             (integer? (string=? suite "lofi-integer"))

             (wasm (build-path "oracle.wasm")))
        (write-json (build-path "oracle.json") (list->vector cases))

        (build-guest (fixture suite (if domain? "domain.sld" "oracle.sld")) wasm
                     (list (if integer? "integer-probe" "probe")))
        (when domain? (link-forms wasm))
        (for-each (lambda (form)
                    (let ((artifact (if domain? (build-path (string-append form ".wasm"))
                                        (if (string=? form "raw") (string-append wasm ".raw.wasm") wasm))))
                      (checked (string-append "oracle-" form)
                               (node (fixture suite "oracle.mjs") artifact (build-path "oracle.json"))))) '("raw" "optimized"))
        (complete! "independent exact-number corpus on raw and optimized Wasm"
                   `((passed . #t) (cases . ,(length cases)) (diagnostic_only . #t) (oracle . "committed independent exact answers")))))

    ;; ---- Exhaustive reduced-radix and production arithmetic ----

    (define (run-integer-units)
      (let* ((production (read-text (path "src/lofi/integer.sld")))
             (reduced (read-text (fixture "lofi-integer" "small-radix/lofi/integer.sld")))
             (expected (regexp-replace (pcre->regexp "1073741824") production "4"))
             (expected (regexp-replace (pcre->regexp "\\(ann 30 I64\\)") expected "(ann 2 I64)")))
        (assert-equal reduced expected "small radix differs beyond its two constants"))
      (for-each
       (lambda (radix)
         (let* ((name (number->string radix)) (wasm (build-path (string-append "unit-" name ".wasm"))))
           (build-guest (fixture "lofi-integer" "unit.sld") wasm '()
                        (if (= radix 4) (list "-I" (fixture "lofi-integer" "small-radix")) '()))
           (assert-equal (contains? (read-text (string-append wasm ".wat")) "(i64.const 1073741824)") (= radix 1073741824))
           (for-each (lambda (artifact) (checked (string-append "unit-" name (if (string=? artifact wasm) "-optimized" "-raw"))
                                                 (node (fixture "lofi-integration" "run.mjs") artifact "42")))
                     (list wasm (string-append wasm ".raw.wasm"))))) '(4 1073741824)))
    (define (run-integer)
      (assert-that (member (argument-value "--only" #f) '(#f "units" "oracle")) "unknown integer test group")
      (unless (equal? (argument-value "--only" #f) "oracle") (run-integer-units))
      (unless (equal? (argument-value "--only" #f) "units")
        (for-each (lambda (case)
                    (let* ((source (fixture "lofi-integer" (string-append "reject-" (car case) ".sld")))
                           (record (checked (car case) (list (path "scripts/build-lofi") source (build-path (string-append (car case) ".wasm")))
                                            `((status . error) (error . ,(cadr case))))))
                      (assert-that (contains? (field record 'stderr) source) record)))
                  '(("mixed" "no compatible overload signature") ("private" "unbound") ("limbs" "unbound")))
        (numeric-corpus "lofi-integer" #f)))

    ;; ---- Arithmetic and narrowing preserve operand evaluation and required traps ----

    (define (run-arithmetic-or-narrowing suite)
      (let* ((arithmetic? (string=? suite "lofi-arithmetic"))
             (cases (rows (read-json (fixture suite "cases.json"))))
             (wasm (build-path "program.wasm"))
             (exports (if arithmetic?
                          '("calculate-i32" "calculate-i64" "calculate-f32" "calculate-f64"
                            "discard-i32" "discard-i64" "discard-f32" "discard-f64" "constant-arithmetic")
                          '("narrow-integer" "narrow-float" "narrow-control" "effect-count"))))
        (write-json (build-path "cases.json") (list->vector cases))
        (build-guest (fixture suite "main.sld") wasm exports)

        (for-each (lambda (artifact) (checked (if (string=? artifact wasm) "optimized" "raw")
                                              (node (fixture suite "run.mjs") artifact (build-path "cases.json"))))
                  (list wasm (string-append wasm ".raw.wasm")))

        (when arithmetic? (arithmetic-libraries))
        (complete! "arithmetic and checked narrowing on raw/optimized Wasm"
                   `((passed . #t) (cases . ,(length cases)) (diagnostic_only . #t)))))
    (define (arithmetic-libraries)
      (let ((wasm (build-path "libraries.wasm")))
        (build-guest (fixture "lofi-arithmetic" "libraries.sld") wasm '()) (link-forms wasm)
        (for-each (lambda (form) (checked (string-append "libraries-" form)
                                          (node (fixture "lofi-arithmetic" "libraries.mjs") (build-path (string-append form ".wasm"))))) '("raw" "optimized"))))

    ;; ---- All Unicode encodings and exact literal allocation boundaries ----

    (define (run-bytes)
      (let* ((oracle (build-path "unicode.bin")) (wasm (build-path "unicode.wasm")))
        (checked "unicode-oracle" (rust-harness "unicode" oracle)
                 '())
        (assert-equal (bytevector-length (read-bytes oracle)) (* 1112064 12))
        (write-json (build-path "oracle.json") `((scalars . 1112064) (bytes . ,(* 1112064 12)) (sha256 . ,(file-sha256 oracle))
                                                 (oracle . "Rust char::encode_utf8; all Unicode scalars")))
        (build-guest (fixture "lofi-bytes" "unicode.sld") wasm '("encode-scalar" "decode-scalar"))
        (for-each (lambda (artifact) (checked (if (string=? wasm artifact) "unicode-optimized" "unicode-raw")
                                              (node (fixture "lofi-bytes" "unicode.mjs") artifact oracle) '((stdout . "scalars 1112064\n"))))
                  (list wasm (string-append wasm ".raw.wasm"))))
      (let ((wasm (build-path "literal.wasm")))
        (build-guest (fixture "lofi-bytes" "literal-10000.sld") wasm '())
        (for-each (lambda (artifact) (checked "literal-wasm" (node (fixture "lofi-integration" "run.mjs") artifact "42")))
                  (list wasm (string-append wasm ".raw.wasm")))

        (checked "literal-rejected" (list (path "scripts/build-lofi") (fixture "lofi-bytes" "literal-10001.sld") (build-path "too-large.wasm"))
                 '((status . error) (error . "literal-10001.sld:4:20: bytevector literal exceeds Wasm array.new_fixed limit")))))

    ;; ---- Independent floating answers include nonfinite values and zero signs ----

    (define (parse-real text)
      (cond ((member text '("Infinity" "inf" "+inf.0")) +inf.0)
            ((member text '("-Infinity" "-inf" "-inf.0")) -inf.0)
            ((member text '("NaN" "nan" "+nan.0")) +nan.0)
            (else (let ((value (string->number text)))
                    (assert-that (real? value) "invalid floating observation" text)
                    ;; V8 prints -0 without a decimal point; exact parsing loses its sign.
                    (if (zero? value) (if (starts? text "-") -0.0 0.0) (inexact value))))))
    (define (check-floats actual expected tolerance)
      (let ((values (map parse-real (lines actual))) (targets (map parse-real expected)))
        (assert-equal (length values) (length targets))
        (for-each (lambda (value target)
                    (assert-that (cond ((nan? target) (nan? value))
                                       ((zero? target) (and (zero? value) (eqv? (< (/ 1.0 value) 0) (< (/ 1.0 target) 0))))
                                       ((infinite? target) (= value target))
                                       (else (and (finite? value) (<= (abs (- value target)) (* tolerance (abs target)))))) value target))
                  values targets)))
    (define (run-math scalars?)
      (let* ((data (read-json (if scalars? (fixture "lofi" "scalar-services.json") (path "tests/lofi-math.json"))))
             (cases (if scalars? (rows data) '()))
             (valid (if scalars? (filter (lambda (case) (not (string=? (vector-ref case 4) "trap"))) cases) '()))
             (arguments (if scalars? (append-map (lambda (case) (take (strings case) 4)) valid) (strings (field data 'inputs))))
             (expected (if scalars? (map (lambda (case) (vector-ref case 4)) valid) (strings (field data 'expected))))
             (wasm (build-path "program.wasm"))
             (runner (if scalars? (fixture "lofi" "scalar-services.mjs") (path "tests/lofi-math.mjs"))))
        (build-guest (if scalars? (fixture "lofi" "scalar-services.sld") (path "tests/lofi-math.sld")) wasm
                     (if scalars? '("unary" "binary" "character") '("trigonometry")))
        (link-forms wasm)
        (for-each (lambda (form)
                    (check-floats (command-output (string-append form "-run")
                                                  (apply node runner (build-path (string-append form ".wasm")) arguments)) expected (if scalars? 3e-15 2e-15))) '("raw" "optimized"))

        (when scalars?
          (indexed-for-each (lambda (index case)
                              (let ((arguments (take (strings case) 4)))
                                (for-each (lambda (form) (checked (string-append form "-overflow-" (number->string index))
                                                                  (apply node runner (build-path (string-append form ".wasm")) arguments)
                                                                  '((status . 1) (error . "RuntimeError: unreachable")))) '("raw" "optimized"))))
                            (filter (lambda (case) (string=? (vector-ref case 4) "trap")) cases)))
        (complete! "independent scalar math on both Wasm forms" `((passed . #t) (cases . ,(length expected))))))
    (define (run-target-suite suite)
      (cond ((string=? suite "lofi-integer") (run-integer))
            ((string=? suite "lofi-numbers") (numeric-corpus suite (argument-present? "--domain")))
            ((member suite '("lofi-arithmetic" "lofi-narrowing")) (run-arithmetic-or-narrowing suite))
            ((string=? suite "lofi-bytes") (run-bytes))
            (else (run-math (string=? suite "lofi-scalars")))))))
