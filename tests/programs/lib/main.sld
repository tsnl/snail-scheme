;; The library error-main-library.sld imports, whose name, (main), is the
;; program's own.
(define-library (main)
  (import
   (snail core base)
   (snail core io))
  (export
   from-library)
  (begin
    (define from-library 1)
    (write-line "the library's statement")))
