;; Core value bindings implemented by WasmGC helpers and ABI Rust services.
;; Higher-level procedures and derived syntax live in bootstrap/scheme.
(define-library (snail-scheme bootstrap)
  (export bootstrap-primitive-names iverson-primitive-arities)
  (import (scheme base))
  (begin
    (define iverson-primitive-arities
      '((%iverson-array . 3) (%iverson-array? . 1) (%iverson-shape . 1)
        (%iverson-dtype . 1) (%iverson-cast . 2)
        (%iverson-data . 1) (%iverson-ref . 2) (%iverson-iota . 2)
        (%iverson-reshape . 2) (%iverson-transpose . 1) (%iverson-binary . 3)
        (%iverson-reduce . 3) (%iverson-matmul . 2)
        (%iverson-gather . 2) (%iverson-scatter . 4)))

    (define bootstrap-primitive-names
      (append '(+ - * / = < <= > >= quotient remainder modulo
                  exact inexact exact? floor ceiling truncate round expt exact-integer-sqrt
                  make-rectangular make-polar real-part imag-part magnitude angle
                  numerator denominator
                  acos asin atan cos exp finite? infinite? log nan? sin sqrt tan
                  eq? eqv? boolean? number? real? inexact? integer? exact-integer? pair? null?
                  symbol? string? char? vector? bytevector? procedure?
                  cons car cdr set-car! set-cdr!
                  vector vector-ref vector-set! vector-length make-vector
                  string make-string string-set! string-ref string-length string-append substring string=?
                  string->symbol symbol->string string->number number->string
                  char->integer integer->char char=? char<? char<=? char>? char>=?
                  char-ci=? char-alphabetic? char-numeric? char-whitespace?
                  char-ci<? char-ci<=? char-ci>? char-ci>=? char-upcase char-downcase char-foldcase
                  char-upper-case? char-lower-case? digit-value
                  string<? string<=? string>? string>=? string-ci=? string-ci<? string-ci<=? string-ci>? string-ci>=?
                  string-upcase string-downcase string-foldcase
                  bytevector make-bytevector bytevector-length bytevector-u8-ref bytevector-u8-set!
                  values call-with-values call-with-current-continuation call/cc apply error
                  open-input-file open-output-file open-binary-input-file file-exists? delete-file close-port
                  port? input-port? output-port? input-port-open? output-port-open? textual-port? binary-port?
                  read read-char peek-char read-line read-string read-bytevector bytevector-copy bytevector-append utf8->string string->utf8 eof-object? eof-object
                  open-input-string open-output-string get-output-string display write write-char write-string flush-output-port newline
                  %current-input-port %current-output-port %current-error-port
                  %set-current-input-port! %set-current-output-port! %set-current-error-port!
                  command-line exit get-environment-variable find-artifact current-second current-jiffy jiffies-per-second
                  string-contains %hash-by-identity %eqv-hash %equal-hash %string-hash %string-ci-hash
                  %make-record-type %make-record %record? %record-ref %record-set!)
              (map car iverson-primitive-arities)))))
