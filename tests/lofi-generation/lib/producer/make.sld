;; Producers return library source text. Each takes the generated library's
;; name, so the recipe key and the produced definition agree.
(define-library (producer make)
  (import
   (scheme base)
   (only (lofi base) string-append string=? i32->i64)
   (only (lofi scalar-text) i64->string))
  (export constant-library dependent-library importing-library ill-typed-library produce)
  (begin
    (define (number-text value) (i64->string (i32->i64 value)))
    (define (import-clause imports)
      (if (string=? imports "") "" (string-append " (import " imports ")")))
    (define (exported-library name imports body)
      (string-append "(define-library " name (import-clause imports) " (export (rename answer value))"
                     " (begin (def answer (-> I32) (lambda () " body "))))"))
    (define (constant-library name value)
      (exported-library name "" (number-text value)))
    (define (dependent-library name offset)
      (exported-library name "(generated support) (consumer arithmetic)"
                        (string-append "(add (value) " (number-text offset) ")")))
    (define (importing-library name provider)
      (string-append "(define-library " name (import-clause provider) ")"))
    (define (ill-typed-library name)
      (string-append "(define-library " name "\n  (begin (def answer I32 #t)))"))
    (define (produce) (constant-library "(generated hygiene)" 42))))
