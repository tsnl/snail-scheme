;; Run from the repository root with chibi-scheme -I src examples/extension/build.scm.
;; The Rust functions live in src/interop_example.rs and are built into the runtime.
(import (scheme base) (snail-scheme build))

(define foreign
  (map (lambda (name) (cons name "snail.rust"))
       '(rust-triple rust-remember rust-recalled rust-call rust-forget rust-root-stress)))

(build-wasm "." "examples/extension.scm" "build/extension.wasm" foreign)
(run-wasm "." "build/extension.wasm" '())
