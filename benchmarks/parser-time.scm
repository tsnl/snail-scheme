;; Chibi-hosted parser timing in microseconds. Imports and file reading are
;; outside the timer; grammar values are already initialized. Validate the
;; parsed datums with the host reader after timing. Use fresh processes.
(import (scheme base) (scheme file) (scheme read) (scheme write)
        (scheme time) (scheme process-context)
        (snail-scheme reader) (snail-scheme parser)
        (snail-scheme syntax) (snail-scheme syntax-parser))
(define arguments (cdr (command-line)))
(unless (= (length arguments) 1) (error "usage: parser-time.scm SOURCE"))
(define reader (file->reader (car arguments)))
(define start (current-jiffy))
(define result (s-file reader))
(define elapsed (- (current-jiffy) start))
(unless (parse-result-ok? result) (error "parse failed"))
(define expected
  (call-with-input-file (car arguments)
    (lambda (port)
      (let loop ((forms '()))
        (let ((form (read port)))
          (if (eof-object? form) (reverse forms) (loop (cons form forms))))))))
(unless (equal? expected (map syntax->datum (parse-result-value result)))
  (error "datums differ from host reader"))
(write (quotient (* elapsed 1000000) (jiffies-per-second))) (newline)
