(define-library (snail-scheme reader)
  (export
   <reader>
   make-reader
   reader?
   reader-filename
   reader-chars
   reader-line
   reader-column
   file->reader
   string->reader
   list->reader
   reader-eof?
   peek-reader
   next-reader
   reader-loc)

  (import
   (scheme base)
   (only (snail-scheme common) file->string)
   (snail-scheme source))

  (begin

    ;; ---- Character reader ----

    (define-record-type <reader>
      (make-reader
       filename ; filename to include in syntax `<loc>`
       chars ; list of chars
       line ; the 1-indexed line of the first character
       column) ; the 1-indexed column of the first character
      reader?
      (filename reader-filename)
      (chars reader-chars)
      (line reader-line)
      (column reader-column))

    (define (file->reader filename)
      (string->reader filename (file->string filename)))

    (define (string->reader filename str)
      (let ((chars (string->list str)))
        (list->reader filename chars)))

    (define (list->reader filename chars)
      (make-reader filename chars 1 1))

    (define (reader-eof? reader)
      (null? (peek-reader reader)))

    (define (peek-reader reader)
      (let ((chars (reader-chars reader)))
        (if (null? chars) '() (car chars))))

    (define (next-reader reader)
      (let* ((filename (reader-filename reader))
             (old-chars (reader-chars reader))
             (old-line (reader-line reader))
             (old-column (reader-column reader))
             (car-char (car old-chars))
             (next-chars (cdr old-chars))
             ;; Count CRLF as one line ending, and also accept a standalone CR.
             (newline? (or (eqv? car-char #\newline)
                           (and (eqv? car-char #\return)
                                (not (and (pair? next-chars)
                                          (eqv? (car next-chars) #\newline))))))
             (next-line (if newline? (+ 1 old-line) old-line))
             (next-column (if newline? 1 (+ 1 old-column))))
        (make-reader filename next-chars next-line next-column)))

    (define (reader-loc reader)
      (make-loc
       (reader-filename reader)
       (reader-line reader)
       (reader-column reader))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-reader)
    (import (snail-scheme test-utils))
    (begin
      ;; Compare location fields explicitly instead of relying on record equality.
      (define (test-value value)
        (cond
         ((loc? value) (list (loc-filename value) (loc-line value) (loc-column value)))
         ((pair? value) (cons (test-value (car value)) (test-value (cdr value))))
         (else value)))

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
        (run-test test-reader-positions))
      ))))
