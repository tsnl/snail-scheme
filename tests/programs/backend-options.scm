;; One ordinary application of the public option reader, in Chibi, Wasm, and native code.
(import (scheme base) (scheme write) (scheme process-context) (snail-scheme options))

(define specification
  (make-args-spec
   '((key-val-list ("-I") "Prepend a library directory." "DIRECTORY")
     (key-val ("--output" "-o") "Write a file." "FILE")
     (key-val-list ("--file" "-f") "Read files." "FILE")
     (counter ("-v" "--verbose") "Increase verbosity.")
     (flag ("-h" "--help") "Show help."))
   "options-demo" "Demonstrate typed options in an ordinary Scheme application."))
(define arguments (cdr (command-line)))
(define sample '("-vvv" "-Ifirst" "first.scm" "-o" "old" "--output=a=b" "-I" "second"
                 "--file" "a" "-fb" "--verbose" "--" "script.scm" "-Ithird" "--" ""))

(unless (args-spec? specification) (error "expected an argument specification"))
(define args (parse-options specification (if (null? arguments) sample arguments)))
(if (args-ref args "-h")
    (display (options-help specification))
    (begin
      (write (args-posargs args)) (newline)
      (write (args-options args)) (newline)))
