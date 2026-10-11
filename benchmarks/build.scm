;; Build artifacts before measuring execution; edit the script to choose cases.
(import (scheme base) (snail-scheme build) (snail-scheme chromium-trace)
        (only (chibi filesystem) create-directory*))
(create-directory* "build")
(with-chromium-trace-to "build/cpu.trace.json"
  (lambda () (build-wasm "." "benchmarks/cpu.scm" "build/cpu.wasm")))
