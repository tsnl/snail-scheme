;; Binaryen optimizes guest Wasm before the complete program is linked.
;; Importing this library performs no tool checks or compilation.
(define-library (lofi host wasm-optimize)
  (export wasm-features check-binaryen-tools assemble-wasm optimize-wasm)
  (import
   (scheme base)
   (scheme file)
   (scheme write)
   (lofi host build-host))
  (begin

    ;; ---- Explicit dependency preflight ----

    ;; Arguments remain separate argv entries, including paths with spaces.
    ;; The fixed shell expression suppresses successful version output and tests
    ;; the selected override itself; a broken override never falls back to PATH.
    (define (check-binaryen-tool variable default)
      (let ((tool (tool-name variable default)))
        (unless (zero? (process-status
                        (list "sh" "-c" "command -v \"$1\" >/dev/null 2>&1 && \"$1\" --version >/dev/null 2>&1"
                              "snail-binaryen-preflight" tool) "." #f "sh"))
          (error (string-append "Binaryen tool is missing or unusable: " tool
                                ". Install Binaryen on PATH (the repository nix-shell includes it), or set " variable
                                " to its executable path.")))))

    (define (check-binaryen-tools . selected)
      (for-each (lambda (entry) (check-binaryen-tool (car entry) (cdr entry)))
                (if (null? selected)
                    '(("WASM_AS" . "wasm-as") ("WASM_OPT" . "wasm-opt")
                      ("WASM_DIS" . "wasm-dis") ("WASM_MERGE" . "wasm-merge"))
                    (car selected))))

    ;; ---- Shared Wasm optimization ----

    (define wasm-features
      '("--mvp-features" "--enable-gc" "--enable-reference-types" "--enable-tail-call"
        "--enable-mutable-globals" "--enable-sign-ext" "--enable-bulk-memory"
        "--enable-nontrapping-float-to-int"))

    (define (assemble-wasm input output)
      (run-command "build.assemble"
                   (append (list (tool-name "WASM_AS" "wasm-as") "-g") wasm-features
                           (list input "-o" output))))

    ;; Exports are the ABI link contract. Preserve them here; complete Wasm
    ;; programs receive a separate optimization after linking the Rust runtime.
    (define (optimize-wasm input output)
      (run-command "build.optimize-wasm"
                   (append (list (tool-name "WASM_OPT" "wasm-opt") "-g") wasm-features
                           (list "-O3" "--closed-world" "--always-inline-max-function-size=40"
                                 "--converge" input "-o" output))))

    ))
