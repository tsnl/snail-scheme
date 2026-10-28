;; Assertions and inputs shared by the compiler's unit tests.
(define-library (snail stage0 testing)
  (export
   expect
   generated-library-bytes)
  (import
   (scheme base)
   (scheme read)
   (scheme write))
  (begin

    (define (expect actual expected)
      (unless (equal? actual expected)
        (let ((port (current-error-port)))
          (display "expected: " port) (write expected port) (newline port)
          (display "actual:   " port) (write actual port) (newline port)
          (error "unit test failed" actual expected))))

    ;; The bytes a producer writes for the library `text` holds, in the
    ;; encoding src/snail/shell/syntax.sld defines: lists, symbols, strings
    ;; and integers, as a vector of byte values, stage 0's Bytes.
    (define (generated-library-bytes text)
      (list->vector (encoded (read (open-input-string text)))))

    (define (encoded datum)
      (cond ((list? datum)
             (append (list 0) (encoded-count (length datum)) (apply append (map encoded datum))))
            ((symbol? datum) (encoded-text 1 (symbol->string datum)))
            ((exact-integer? datum) (encoded-text 2 (number->string datum)))
            ((string? datum) (encoded-text 3 datum))
            (else (error "no generated encoding for" datum))))

    (define (encoded-text tag text)
      (append (list tag) (encoded-count (string-length text))
              (apply append
                     (map (lambda (c) (encoded-count (char->integer c))) (string->list text)))))

    ;; Seven bits to a byte, low bits first.
    (define (encoded-count count)
      (if (< count 128)
          (list count)
          (cons (+ 128 (remainder count 128)) (encoded-count (quotient count 128)))))

    ))
