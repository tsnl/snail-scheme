(import (scheme base) (scheme process-context) (lofi host process) (wasm-reference compiler))
(command-line-main (lambda (arguments)
                     (reference-compiler-main (absolute-path (path-join (path-directory (absolute-path (car (command-line)))) "../../..")) 'asm arguments)))
