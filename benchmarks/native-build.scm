;; Build one complete linked module, then translate that exact binary to native.
;; Run from the checkout: chibi-scheme -I src benchmarks/native-build.scm
(import (scheme base) (snail-scheme build) (snail-scheme native)
        (snail-scheme chromium-trace) (only (chibi filesystem) create-directory*))

(create-directory* "build/native-benchmark")
(with-chromium-trace-to "build/native-benchmark/build.trace.json"
  (lambda ()
    (build-wasm "." "benchmarks/cpu.scm" "build/native-benchmark/cpu.wasm")
    (wasm-file->native-file "." "build/native-benchmark/cpu.wasm" "build/native-benchmark/cpu")))
