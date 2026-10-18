(import (scheme base) (scheme process-context) (lofi host process) (wasm-reference suite))
(command-line-main (lambda (arguments)
                     (reference-suite-main (absolute-path (path-join (path-directory (absolute-path (car (command-line)))) "../..")) arguments)))
