;; (lofi io) for the Chibi host: files and console text with Chibi's ports.
(define-library (lofi io)
  (export
   read-file
   write-file
   file-exists?
   command-line
   write-string
   write-line
   newline)
  (import
   (rename (scheme base) (write-string scheme-write-string) (newline scheme-newline))
   (scheme file)
   (scheme process-context))
  (begin

    (define (read-file path)
      (call-with-input-file path
        (lambda (port)
          (let loop ((chunks '()))
            (let ((chunk (read-string 65536 port)))
              (if (eof-object? chunk) (apply string-append (reverse chunks)) (loop (cons chunk chunks))))))))

    (define (write-file path text)
      (call-with-output-file path (lambda (port) (scheme-write-string text port))))

    (define (write-string text) (scheme-write-string text))

    (define (newline) (scheme-newline))

    (define (write-line text) (scheme-write-string text) (scheme-newline))

    ))
