(import (scheme base) (scheme process-context) (wasm-native process) (wasm-reference compiler))
(command-line-main (lambda (arguments)
                     (reference-compiler-main (absolute-path (path-join (path-directory (absolute-path (car (command-line)))) "../../..")) 'frontend arguments)))
