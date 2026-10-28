;; (snail core io) for the Chibi host: files and console text with Chibi's ports.
(define-library (snail core io)
  (export
   read-file
   read-bytes
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
              (if (eof-object? chunk)
                  (apply string-append (reverse chunks))
                  (loop (cons chunk chunks))))))))

    ;; Snail-Core's Bytes are vectors of integers on this host.
    (define (read-bytes path)
      (let* ((bytes (call-with-port (open-binary-input-file path) read-all-bytes))
             (vector (make-vector (bytevector-length bytes))))
        (do ((index 0 (+ index 1))) ((= index (vector-length vector)) vector)
          (vector-set! vector index (bytevector-u8-ref bytes index)))))
    (define (read-all-bytes port)
      (let loop ((chunks '()))
        (let ((chunk (read-bytevector 65536 port)))
          (if (eof-object? chunk)
              (apply bytevector-append (reverse chunks))
              (loop (cons chunk chunks))))))
    (define (write-file path text)
      (call-with-output-file path (lambda (port) (scheme-write-string text port))))

    (define (write-string text) (scheme-write-string text))

    (define (newline) (scheme-newline))

    (define (write-line text) (scheme-write-string text) (scheme-newline))

    ))
