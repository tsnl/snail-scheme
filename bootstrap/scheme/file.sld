(define-library (scheme file)
  (export open-input-file open-output-file open-binary-input-file call-with-input-file call-with-output-file file-exists?)
  (import (scheme base)
          (only (snail-scheme core) open-input-file open-output-file open-binary-input-file file-exists?))
  (begin
    (define (call-with-input-file path procedure)
      (call-with-port (open-input-file path) procedure))
    (define (call-with-output-file path procedure)
      (call-with-port (open-output-file path) procedure))))
