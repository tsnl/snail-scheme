(define-library (snail-scheme wat)
  (export read-wat wat-number wat-name? wat-text)
  (import (scheme base) (scheme char) (scheme write))
  (begin

    ;; ---- Binaryen's folded text format ----

    ;; The Scheme reader cannot read WAT byte escapes, hexadecimal numbers, or
    ;; identifiers containing Scheme delimiters. This small reader preserves
    ;; atoms as symbols and quoted byte strings as strings; it never expands or
    ;; resolves Scheme syntax. Binaryen validates the binary before disassembly.

    (define (wat-text value)
      (if (symbol? value) (symbol->string value) value))

    (define (wat-name? value)
      (and (symbol? value)
           (> (string-length (symbol->string value)) 0)
           (char=? (string-ref (symbol->string value) 0) #\$)))

    (define (wat-number value)
      (let* ((text (wat-text value))
             (negative? (char=? (string-ref text 0) #\-))
             (start (if (memv (string-ref text 0) '(#\+ #\-)) 1 0))
             (hex? (and (> (string-length text) (+ start 2))
                        (string=? (substring text start (+ start 2)) "0x")))
             (number (string->number (if hex? (substring text (+ start 2)) text)
                                     (if hex? 16 10))))
        (unless number (error "unsupported WAT number" value))
        (if (and hex? negative?) (- number) number)))

    (define (wat-space port)
      (let ((char (peek-char port)))
        (cond ((eof-object? char) char)
              ((char-whitespace? char) (read-char port) (wat-space port))
              ((eqv? char #\;)
               (read-line port)
               (wat-space port))
              (else char))))

    (define (wat-atom port)
      (let loop ((chars '()))
        (let ((char (peek-char port)))
          (if (or (eof-object? char) (char-whitespace? char)
                  (memv char '(#\( #\) #\;)))
              (string->symbol (list->string (reverse chars)))
              (loop (cons (read-char port) chars))))))

    (define (wat-escape port)
      (let* ((char (read-char port))
             (ordinary (assv char '((#\n . #\newline) (#\r . #\return)
                                    (#\t . #\tab) (#\" . #\")
                                    (#\' . #\') (#\\ . #\\)))))
        (if ordinary (cdr ordinary)
            (let ((byte (string->number (string char (read-char port)) 16)))
              (if byte (integer->char byte) (error "invalid WAT byte escape" char))))))

    (define (wat-string port)
      (read-char port)
      (let loop ((chars '()))
        (let ((char (read-char port)))
          (cond ((eof-object? char) (error "unterminated WAT string"))
                ((eqv? char #\") (list->string (reverse chars)))
                ((eqv? char #\\) (loop (cons (wat-escape port) chars)))
                (else (loop (cons char chars)))))))

    (define (wat-list port)
      (read-char port)
      (let loop ((items '()))
        (let ((char (wat-space port)))
          (cond ((eof-object? char) (error "unterminated WAT list"))
                ((eqv? char #\)) (read-char port) (reverse items))
                (else (loop (cons (wat-form port) items)))))))

    (define (wat-form port)
      (case (wat-space port)
        ((#\() (wat-list port))
        ((#\") (wat-string port))
        ((#\)) (error "unexpected WAT closing parenthesis"))
        (else (wat-atom port))))

    (define (read-wat port)
      (when (eof-object? (wat-space port)) (error "empty WAT input"))
      (let ((form (wat-form port)))
        (unless (eof-object? (wat-space port)) (error "trailing WAT form"))
        form)))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-wat)
    (import (snail-scheme test-utils))
    (begin
      (define (test-wat-bytes)
        (let ((form (read-wat (open-input-string "(data $x \"a\\00\\ff\\n\\\\\\\"\") ;; end\n"))))
          (expect (car form) 'data)
          (expect (map char->integer (string->list (car (cddr form)))) '(97 0 255 10 92 34))))

      (define (test-wat-numbers)
        (expect (wat-number (string->symbol "-0x80000000")) (- (expt 2 31)))
        (expect (wat-number (string->symbol "18446744073709551615")) (- (expt 2 64) 1))
        (expect (wat-name? '$name.with:punctuation) #t)
        (expect (wat-name? 'i32.add) #f))

      (define (test-wat-errors)
        (for-each
         (lambda (input)
           (expect (guard (error (else #t)) (read-wat (open-input-string input)) #f) #t))
         '("" "(module" "(module))" "(module) trailing" "(data \"\\xz\")")))

      (define (test-wat)
        (run-test test-wat-bytes)
        (run-test test-wat-numbers)
        (run-test test-wat-errors))))))
