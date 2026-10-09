(define-library (scheme file)
  (export open-input-file open-output-file call-with-input-file call-with-output-file)
  (import (scheme base)
          (only (snail-scheme core) open-input-file open-output-file))
  (begin
    (define (call-with-input-file path procedure)
      (call-with-port (open-input-file path) procedure))
    (define (call-with-output-file path procedure)
      (call-with-port (open-output-file path) procedure))))
