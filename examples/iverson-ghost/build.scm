;; Run from the repository root: chibi-scheme -I src examples/iverson-ghost/build.scm.
(import (scheme base) (scheme process-context) (snail-scheme build)
        (snail-scheme chromium-trace) (only (snail-scheme build-host) create-directory*))

(create-directory* "build")
(exit
 (with-chromium-trace-to "build/iverson-ghost.trace.json"
                         (lambda ()
                           (build-wasm "." "examples/iverson-ghost/main.scm" "build/iverson-ghost.wasm")
                           (run-wasm "." "build/iverson-ghost.wasm" '()))))
