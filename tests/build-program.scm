;; Integration harness: positional operands belong to this script, not the library.
(import (scheme base) (scheme process-context) (snail-scheme build))
(apply build-wasm (cdr (command-line)))
