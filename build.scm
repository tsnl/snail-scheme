;; An ordinary build script. Run from the checkout:
;;   chibi-scheme -I src build.scm
;; Copy or edit this script to choose other programs, artifacts, or execution.
(import (scheme base) (snail-scheme build))

(build-wasm "." "examples/fibonacci.scm" "build/fibonacci.wasm")
(run-wasm "." "build/fibonacci.wasm" '())
