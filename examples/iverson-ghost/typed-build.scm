(import (scheme base) (scheme process-context) (snail-scheme build)
        (snail-scheme chromium-trace) (only (snail-scheme build-host) create-directory*))

(create-directory* "build")
(exit
 (with-chromium-trace-to "build/iverson-typed.trace.json"
                         (lambda ()
                           (build-wasm "." "examples/iverson-ghost/typed.scm" "build/iverson-typed.wasm")
                           (run-wasm "." "build/iverson-typed.wasm" '()))))
