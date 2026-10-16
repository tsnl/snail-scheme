(define-library (producer services)
  (export read-offset)
  (begin (define-extern read-offset "tests.source" "offset" (-> I32))))
