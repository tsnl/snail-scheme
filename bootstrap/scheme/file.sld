(define-library (scheme file)
  (export open-input-file open-output-file open-binary-input-file call-with-input-file call-with-output-file file-exists? delete-file with-input-from-file with-output-to-file)
  (import (scheme base)
          (only (snail-scheme core) open-input-file open-output-file open-binary-input-file file-exists? delete-file))
  (begin
    (define (call-with-input-file path procedure)
      (call-with-port (open-input-file path) procedure))
    (define (call-with-output-file path procedure)
      (call-with-port (open-output-file path) procedure))
    (define (with-input-from-file path thunk)
      (call-with-input-file path
        (lambda (port) (parameterize ((current-input-port port)) (thunk)))))
    (define (with-output-to-file path thunk)
      (call-with-output-file path
        (lambda (port) (parameterize ((current-output-port port)) (thunk)))))))
