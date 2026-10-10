;; Script operands belong to this integration harness, not the compiler library.
(import (scheme base) (scheme process-context) (snail-scheme native))
(apply wasm-file->native-file (cdr (command-line)))
