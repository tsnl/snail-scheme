;; Lower the Binaryen disassembly of an already optimized Wasm artifact.
;; The experiment does not rerun the frontend or optimize the input again.
(import (scheme base) (scheme process-context)
        (snail-scheme wasm-read) (snail-scheme llvm))
(let ((arguments (cdr (command-line))))
  (wasm->llvm-file
   (read-binaryen-module (car arguments) (string-append (cadr arguments) ".reader"))
   (cadr arguments)))
