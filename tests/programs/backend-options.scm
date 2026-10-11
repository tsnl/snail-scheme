;; One ordinary application of the public option reader, in Chibi, Wasm, and native code.
(import (scheme base) (scheme write) (scheme process-context) (snail-scheme options))

(define specification
  (list (option "-I" 'key-val-list "Prepend a library directory." "DIRECTORY")
        (option '("--output" "-o") 'key-val "Write a file." "FILE")
        (option '("--file" "-f") 'key-val-list "Read files." "FILE")
        (option '("-v" "--verbose") 'counter "Increase verbosity.")
        (option '("-h" "--help") 'flag "Show help.")))
(define usage "usage: options-demo [OPTIONS] [FILE ...]")
(define arguments (cdr (command-line)))
(define sample '("-vvv" "-Ifirst" "first.scm" "-o" "old" "--output=a=b" "-I" "second"
                 "--file" "a" "-fb" "--verbose" "--" "script.scm" "-Ithird" "--" ""))

(define args (parse-options specification (if (null? arguments) sample arguments) usage))
(if (args-ref args "-h")
    (display (options-help specification usage))
    (begin
      (write (args-posargs args)) (newline)
      (write (args-options args)) (newline)))
