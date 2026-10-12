(import (scheme base) (scheme process-context) (snail-scheme build)
        (snail-scheme chromium-trace) (only (snail-scheme build-host) create-directory*))

(create-directory* "build")
(exit
 (with-chromium-trace-to "build/typeclasses.trace.json"
                         (lambda ()
                           (build-wasm "." "examples/typeclasses/main.scm" "build/typeclasses.wasm")
                           (run-wasm "." "build/typeclasses.wasm" '()))))
