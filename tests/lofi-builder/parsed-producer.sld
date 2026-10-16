(define-library (builder parsed)
  (import (lofi compiler-builder) (builder rebuild))
  (export build)
  (begin
    (def build (-> I64 I64)
         (lambda (token) (library-token (rebuild-library (checked-library token)))))))
