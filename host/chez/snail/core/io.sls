;; The source compiler uses text files and byte vectors through this boundary.
(library (snail core io)
  (export read-file read-bytes write-file file-exists? command-line write-string write-line newline)
  (import
   (chezscheme))
  (define (read-file path) (call-with-input-file path get-string-all))
  (define (read-bytes path)
    (let* ([bytes (call-with-port (open-file-input-port path) get-bytevector-all)]
           [items (make-vector (if (eof-object? bytes) 0 (bytevector-length bytes)))])
      (do ([i 0 (+ i 1)]) [(= i (vector-length items)) items]
        (vector-set! items i (bytevector-u8-ref bytes i)))))
  (define (write-file path text)
    (call-with-port (open-file-output-port path (file-options no-fail) (buffer-mode block)
                                           (native-transcoder))
      (lambda (port) (put-string port text))))
  (define (write-string text) (put-string (current-output-port) text))
  (define (write-line text) (write-string text) (newline)))
