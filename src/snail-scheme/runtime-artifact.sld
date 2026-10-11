;; The compiler carries its portable Rust runtime as a deployment dependency.
;; Cargo and Binaryen run only in this build stage; the generated library merely
;; resolves the installed file when a build script needs it.
(generate-library (snail-scheme runtime-artifact)
                  (export runtime-artifact-path)
                  (import (scheme base) (snail-scheme generation) (snail-scheme artifacts)
                          (snail-scheme build-host))
                  (begin
                    (define root (generation-source-path "../.."))
                    (define target (string-append root "/build/wasm-runtime"))
                    (define output (generation-output-path "snail-runtime.wat"))
                    (run-command "build.cargo"
                                 (list (tool-name "CARGO" "cargo") "rustc" "--crate-type=cdylib" "--quiet" "--offline" "--release"
                                       "--target" "wasm32-wasip1" "--manifest-path" (string-append root "/Cargo.toml")
                                       "--target-dir" target) root)
                    (run-command "build.runtime-wat"
                                 (list (tool-name "WASM_DIS" "wasm-dis")
                                       (string-append target "/wasm32-wasip1/release/snail_runtime.wasm") "-o" output))
                    (generated-library
                     '((import (scheme base) (snail artifacts))
                       (begin (define (runtime-artifact-path) (artifact-path "snail-runtime.wat"))))
                     (list (make-artifact "snail-runtime.wat" output '())))))
