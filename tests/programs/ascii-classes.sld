(import
 (snail core base)
 (snail core io))

(define (main) (→ Unit) (! output-port)
  (for-each (lambda (number)
              (let ((char (integer->char number)))
                (write-line (string-append (show (char-whitespace? char)) " "
                                           (show (char-numeric? char)) " "
                                           (show (char-alphabetic? char))))))
            (list 9 10 13 32 11 12 47 48 57 58 64 65 90 91 96 97 122 123 160 233 1633 8195)))
