(define-library (snail-scheme test-reader)
  (export
   test-reader)

  (import
   (scheme base)
   (snail-scheme source)
   (snail-scheme reader)
   (snail-scheme test-utils))

  (begin
    (define (test-reader-constructors)
      (for-each
       (lambda (reader)
         (expect (reader-filename reader) "example.scm")
         (expect (reader-chars reader) '(#\a #\newline #\b))
         (expect (test-value (reader-loc reader)) '("example.scm" 1 1)))
       (list (string->reader "example.scm" "a\nb")
             (list->reader "example.scm" '(#\a #\newline #\b))))
      (expect (reader-eof? (string->reader "empty.scm" "")) #t)
      (expect (reader-eof? (list->reader "empty.scm" '())) #t))

    (define (test-file->reader)
      (let* ((filename "tests/programs/p0001.scm")
             (reader (file->reader filename)))
        (expect (list->string (reader-chars reader)) "(display \"Hello, world\")\n")
        (expect (test-value (reader-loc reader)) (list filename 1 1)))
      (expect
       (guard (ex ((file-error? ex) #t))
         (file->reader "tests/programs/p0001.scm/missing.scm")
         #f)
       #t))

    (define (test-reader-positions)
      (define p "<test-reader-positions>")
      (let* ((a (string->reader p "a\nb"))
             (newline (next-reader a))
             (b (next-reader newline))
             (end (next-reader b)))
        (expect (map peek-reader (list a newline b end)) '(#\a #\newline #\b ()))
        (expect (map (lambda (reader) (test-value (reader-loc reader))) (list a newline b end))
                (test-value (list (make-loc p 1 1) (make-loc p 1 2)
                                  (make-loc p 2 1) (make-loc p 2 2))))
        (expect (reader-eof? a) #f)
        (expect (reader-eof? end) #t))
      (for-each
       (lambda (text)
         (let loop ((reader (string->reader p text)))
           (if (reader-eof? reader)
               (expect (test-value (reader-loc reader)) (test-value (make-loc p 2 1)))
               (loop (next-reader reader)))))
       '("\n" "\r" "\r\n")))

    (define (test-reader)
      (run-test test-reader-constructors)
      (run-test test-file->reader)
      (run-test test-reader-positions))))
