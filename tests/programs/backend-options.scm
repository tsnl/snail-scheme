;; One ordinary application of the public option reader, in Chibi, Wasm, and native code.
(import (scheme base) (scheme write) (scheme process-context) (snail-scheme options))

(define declarations
  '(("-I" . #t) ("-o" . #t) ("--output" . #t) ("-v" . #f) ("--verbose" . #f)))
(define arguments (cdr (command-line)))
(define sample '("-v" "-Ifirst" "--output=a=b" "-I" "second" "script.scm" "-v" ""))

(let-values (((options remaining)
              (parse-options declarations (if (null? arguments) sample arguments) "usage: options-demo")))
  (write options) (newline)
  (write remaining) (newline))
