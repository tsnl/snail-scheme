;; Build artifacts before measuring execution; edit the script to choose cases.
(import (scheme base) (snail-scheme build))
(build-wasm "." "benchmarks/cpu.scm" "build/cpu.wasm")
