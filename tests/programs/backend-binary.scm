(import (scheme base) (scheme file) (scheme write))

(define (expect actual expected)
  (unless (equal? actual expected) (error "binary value differs" actual expected)))

;; Binary data crosses AWI only through owned roots, including empty results.
(expect (bytevector-append) (bytevector))
(expect (bytevector-append (bytevector 0 255) (bytevector 128)) (bytevector 0 255 128))
(define original (bytevector 1 2 3))
(define copied (bytevector-copy original 1 3))
(bytevector-u8-set! copied 0 99)
(expect original (bytevector 1 2 3))
(expect copied (bytevector 99 3))
(expect (bytevector-copy original 3) (bytevector))
(expect (string->utf8 "aλ😀z" 1 3) (bytevector 206 187 240 159 152 128))
(expect (utf8->string (bytevector 255 206 187 0 255) 1 4) "λ\x0;")

;; EOF is distinct from an empty request, and binary reads do not decode UTF-8.
(call-with-output-file "build/backend-tests/binary-input"
  (lambda (port) (display "Aλ\x0;" port)))
(call-with-port (open-binary-input-file "build/backend-tests/binary-input")
  (lambda (port)
    (expect (read-bytevector 0 port) (bytevector))
    (expect (read-bytevector 3 port) (bytevector 65 206 187))
    (expect (read-bytevector 3 port) (bytevector 0))
    (expect (eof-object? (read-bytevector 1 port)) #t)
    (expect (read-bytevector 0 port) (bytevector))))
(display "binary IO checks passed\n")
