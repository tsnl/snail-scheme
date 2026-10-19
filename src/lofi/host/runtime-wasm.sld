;; Build and link Rust scalar services through their Wasm ABI and Binaryen.
(define-library (lofi host runtime-wasm)
  (export build-wasm-runtime link-wasm-runtime)
  (import
   (scheme base)
   (scheme cxr)
   (scheme file)
   (chibi filesystem)
   (chibi string)
   (chibi regexp)
   (only (srfi 1) any)
   (lofi host process)
   (lofi host wasm-optimize))
  (begin

    ;; ---- Runtime Wasm ABI ----

    (define adapter
      "(module\n  (import \"snail.library\" \"snail:report-error\" (func $report (param i32 i32)))\n  (import \"snail.library\" \"snail:io/close-all\" (func $close (result i32)))\n  (export \"diagnostics/report-error\" (func $report))\n  (export \"close-resources\" (func $close)))\n")
    (define (build-wasm-runtime runtime-root)
      (let ((target (path-join runtime-root "build/wasm-runtime")))
        (run-command! (list (tool-name "CARGO" "cargo") "rustc" "--crate-type=cdylib" "--quiet" "--offline"
                            "--release" "--target" "wasm32-wasip1" "--manifest-path" (path-join runtime-root "Cargo.toml")
                            "--target-dir" target))
        (path-join target "wasm32-wasip1/release/snail_runtime.wasm")))
    (define (disassemble input output)
      (run-command! (list (tool-name "WASM_DIS" "wasm-dis") input "-o" output))
      (read-text output))
    (define (check-exports text)
      ;; Binaryen emits top-level declarations on their own indented lines. Avoid
      ;; repeatedly searching the entire module with a character-indexed regexp.
      (for-each
       (lambda (line)
         (when (string-prefix? " (export \"" line)
           (let* ((match (regexp-search (rx "(export \"" ($ (+ (~ #\"))) "\"") line))
                  (name (and match (regexp-match-submatch match 1))))
             (when (or (not name) (member name '("memory" "_initialize" "close-resources"))
                       (string-prefix? "snail:" name) (string-prefix? "diagnostics/" name))
               (error "program uses a reserved runtime export name" name)))))
       (string-split text #\newline)))

    (define (unresolved-runtime-import? text)
      (any (lambda (line)
             (any (lambda (module) (string-prefix? (string-append " (import \"snail." module "\"") line))
                  '("abi" "library" "platform")))
           (string-split text #\newline)))

    ;; ---- Retained merge and optimization ----

    (define (link-wasm-runtime source output provider diagnostic?)
      (let* ((adapter-wat (string-append output ".adapter.wat")) (adapter-wasm (string-append output ".adapter.wasm"))
             (linked (string-append output ".linked.wasm")))
        (when (or (paths-alias? source output) (paths-alias? provider output))
          (error "link output must not replace an input"))
        (create-directory* (path-directory output))
        (parameterize ((current-command-log (string-append output ".link.json")) (current-command-records '()))
          (check-exports (disassemble source (string-append output ".input.wat")))
          (write-text adapter-wat adapter)
          (run-command! (append (list (tool-name "WASM_AS" "wasm-as")) wasm-features (list adapter-wat "-o" adapter-wasm)))
          (run-command! (append (list (tool-name "WASM_MERGE" "wasm-merge") "-g") wasm-features
                                (list source "snail.abi" provider "snail.library" adapter-wasm "snail.platform" "-o" linked)))
          (run-command! (append (list (tool-name "WASM_OPT" "wasm-opt") "-g") wasm-features
                                '("--remove-exports" "--pass-arg=remove-exports@snail:*,diagnostics/*")
                                (if diagnostic? '("--remove-unused-module-elements")
                                    '("-O3" "--closed-world" "--always-inline-max-function-size=40" "--converge"))
                                (list linked "-o" output)))
          (when (unresolved-runtime-import? (disassemble output (string-append output ".wat")))
            (error "linked program retains an unresolved runtime import")))
        0))
    ))
