;; Serialize structured Wasm into the text format accepted by Binaryen.
;; This module has no source-language analysis or compilation dependencies.
(define-library (wasm-native wasm)
  (export write-wasm)
  (import
   (scheme base)
   (scheme cxr)
   (scheme write)
   (wasm-native chromium-trace))
  (begin

    ;; ---- Wasm text ----

    ;; Generated function identifiers use plain WAT tokens. Foreign import names
    ;; are arbitrary UTF-8 strings and require WAT byte escapes, not Scheme's.
    (define (write-wat-string text port)
      (display "\"" port)
      (let ((bytes (string->utf8 text)))
        (let loop ((index 0))
          (if (< index (bytevector-length bytes))
              (begin (write-wat-byte (bytevector-u8-ref bytes index) port)
                     (loop (+ index 1))))))
      (display "\"" port))

    (define (write-wat-byte byte port)
      (if (and (<= 32 byte 126) (not (memv byte '(34 92))))
          (display (integer->char byte) port)
          (begin (display "\\" port)
                 (if (< byte 16) (display "0" port))
                 (display (number->string byte 16) port))))

    (define (write-import definition port)
      (display "(import " port)
      (write-wat-string (cadr definition) port) (display " " port)
      (write-wat-string (caddr definition) port) (display " " port)
      (write-simple (cadddr definition) port) (display ")" port))

    (define (write-definition definition port)
      (cond ((eq? (car definition) 'import) (write-import definition port))
            ((negative-infinity? definition) (write-with-infinity definition port))
            (else (write-simple definition port)))
      (newline port))

    ;; Scheme quotes the WAT token -inf as a symbol. Only definitions containing
    ;; that exceptional leaf need a Scheme walk; the ordinary path stays native.
    (define (negative-infinity? datum)
      (cond ((pair? datum) (or (negative-infinity? (car datum)) (negative-infinity? (cdr datum))))
            ((symbol? datum) (eq? datum (string->symbol "-inf")))
            (else #f)))

    (define (write-with-infinity datum port)
      (cond ((pair? datum)
             (display "(" port)
             (write-with-infinity (car datum) port)
             (for-each (lambda (item) (display " " port) (write-with-infinity item port)) (cdr datum))
             (display ")" port))
            ((eq? datum (string->symbol "-inf")) (display "-inf" port))
            (else (write-simple datum port))))

    (define write-wasm
      (chromium-trace "write-wasm" (lambda (datum port)
                                     (display "(module\n" port)
                                     (for-each (lambda (definition) (write-definition definition port)) (cdr datum))
                                     (display ")\n" port))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-wasm)
    (import
     (wasm-native test-utils))
    (begin
      (define (test-wat-leaves)
        (let ((port (open-output-string)))
          (write-import `(import ,(string #\" #\\ #\newline #\λ (integer->char 0)) "f"
                                 (func $f (param i32))) port)
          (expect (get-output-string port)
                  "(import \"\\22\\5c\\0a\\ce\\bb\\00\" \"f\" (func $f (param i32)))"))
        (let ((port (open-output-string)))
          (write-definition '(global $infinity f64 (f64.const -inf)) port)
          (expect (get-output-string port) "(global $infinity f64 (f64.const -inf))\n")))
      (define (test-wasm) (run-test test-wat-leaves))))))
