;; Integration harness for custom native hosts; normal builds use (snail-scheme native).
(import (scheme base) (scheme process-context) (snail-scheme llvm))
(apply wasm-file->llvm-file (cdr (command-line)))
