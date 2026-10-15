;; Decode bounded JSON messages without changing control-character meanings.
(define-library (snail-tools json)
  (export json-read json-write string->json json->string)
  (import (scheme base) (scheme write)
          (rename (only (chibi json) json-read json-write json->string) (json-read host-json-read))
          (only (chibi io) port->string))
  (begin

    ;; ---- Preserve all standard escapes before the pinned host parser ----

    (define (write-json-escape character output)
      ;; Chibi 0.12 otherwise decodes these escapes as the letters b, f and r.
      (let ((unicode (case character ((#\b) "\\u0008") ((#\f) "\\u000c") ((#\r) "\\u000d") (else #f))))
        (if unicode (display unicode output)
            (begin (write-char #\\ output)
                   (unless (eof-object? character) (write-char character output))))))
    (define (normalized-json text)
      (let ((input (open-input-string text)) (output (open-output-string)))
        (let loop ((quoted? #f))
          (let ((character (read-char input)))
            (cond ((eof-object? character) (get-output-string output))
                  ((and quoted? (char=? character #\\))
                   (write-json-escape (read-char input) output) (loop #t))
                  (else (write-char character output)
                        (loop (if (char=? character #\") (not quoted?) quoted?))))))))
    (define (json-message-ended? input)
      (let ((character (read-char input)))
        (cond ((eof-object? character) #t)
              ((memv character '(#\space #\tab #\newline #\return)) (json-message-ended? input))
              (else #f))))
    (define (string->json text)
      (call-with-port (open-input-string (normalized-json text))
        (lambda (input)
          (let ((value (host-json-read input)))
            (unless (json-message-ended? input) (error "JSON message has trailing input")) value))))
    (define (json-read . ports)
      ;; Callers supply finite file, metadata or already-framed message ports.
      (string->json (port->string (if (null? ports) (current-input-port) (car ports))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-json)
    (import (snail-scheme test-utils))
    (begin
      (define (test-standard-escapes)
        (expect (map char->integer (string->list (string->json "\"\\\"\\\\\\/\\b\\f\\n\\r\\t\\u0000\"")))
                '(34 92 47 8 12 10 13 9 0))
        (expect (string->json "[\"\\\\r\",\"\\\\b\",\"\\\\f\",\"\\\\\\r\"]")
                (vector "\\r" "\\b" "\\f" (string #\\ #\return)))
        (expect (string->json "\"λ\\ud83d\\ude42\\u10ff\"") "λ🙂ჿ"))
      (define (test-control-roundtrip)
        (let ((value (list (cons 'text (list->string (map integer->char '(0 1 8 9 10 12 13 31 34 92 128578)))))))
          (expect (string->json (json->string value)) value)
          (expect (json-read (open-input-string (json->string value))) value))
        (expect (normalized-json "\\r \"\\r\"") "\\r \"\\u000d\""))
      (define (test-complete-message)
        (expect (string->json " {\"text\": [\"\\r\", \"\\\\r\"]} \t\r\n")
                (list (cons 'text (vector (string #\return) "\\r"))))
        (for-each (lambda (text)
                    (expect (guard (failure (else #t)) (string->json text) #f) #t))
                  '("" " " "[] {}" "{} garbage" "\"text\" false")))
      (define (test-json)
        (run-test test-standard-escapes)
        (run-test test-control-roundtrip)
        (run-test test-complete-message))))
   (else)))
