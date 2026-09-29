(define-library (snail-scheme test-reader)
  (export
    test-reader)

  (import
    (scheme base)
    (snail-scheme reader)
    (snail-scheme test-utils))

  (begin
    (define (test-reader-positions)
      (let* ((a (string->reader "a\nb"))
             (newline (next-reader a))
             (b (next-reader newline))
             (end (next-reader b)))
        (expect (map peek-reader (list a newline b end)) '(#\a #\newline #\b ()))
        (expect (map (lambda (reader) (test-value (reader-loc reader))) (list a newline b end))
          (test-value (list (at 1 1) (at 1 2) (at 2 1) (at 2 2))))
        (expect (reader-eof? a) #f)
        (expect (reader-eof? end) #t))
      (for-each
        (lambda (text)
          (let loop ((reader (string->reader text)))
            (if (reader-eof? reader)
              (expect (test-value (reader-loc reader)) (test-value (at 2 1)))
              (loop (next-reader reader)))))
        '("\n" "\r" "\r\n")))

    (define (test-reader)
      (run-test test-reader-positions))))
