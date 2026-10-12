;; The same folded-text decoder runs in Chibi and in the installed interpreter.
(import (scheme base) (scheme file) (scheme process-context)
        (snail-scheme wasm-read) (snail-scheme llvm))
(define arguments (cdr (command-line)))
(wasm->llvm-file (read-binaryen-module (car arguments) (string-append (cadr arguments) ".reader.scm"))
                 (cadr arguments))
