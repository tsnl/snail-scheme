;; The native boundary used by the initial, unoptimized backend. Higher-level
;; procedures and derived syntax live in bootstrap/scheme rather than Rust.
(define-library (snail-scheme bootstrap)
  (export bootstrap-primitive-names)
  (import (scheme base))
  (begin
    (define bootstrap-primitive-names
      '(+ - * / = < <= > >= quotient remainder modulo
          eq? eqv? boolean? number? real? inexact? integer? exact-integer? pair? null?
          symbol? string? char? vector? bytevector? procedure?
          cons car cdr set-car! set-cdr!
          vector vector-ref vector-set! vector-length make-vector
          string string-ref string-length string-append substring string=?
          string->symbol symbol->string string->number number->string
          char->integer integer->char char=? char<? char<=? char>? char>=?
          char-ci=? char-alphabetic? char-numeric? char-whitespace?
          bytevector bytevector-length bytevector-u8-ref bytevector-u8-set!
          values call-with-values apply error
          open-input-file open-output-file close-port read-char read-string eof-object?
          open-output-string get-output-string display write newline
          %current-input-port %current-output-port %current-error-port
          %set-current-input-port! %set-current-output-port! %set-current-error-port!
          command-line exit current-jiffy jiffies-per-second
          string-contains collect-garbage gc-statistics
          %make-record-type %make-record %record? %record-ref %record-set!))))
