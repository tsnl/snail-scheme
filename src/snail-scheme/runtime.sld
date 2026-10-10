;; Nonstandard runtime operations.
(define-library (snail-scheme runtime)
  (export string-contains)
  (import (only (snail-scheme core) string-contains)))
