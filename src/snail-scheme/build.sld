;; Host-independent build operations. Scripts choose inputs, outputs, and execution;
;; importing this library never reads command-line arguments or starts a build.
(define-library (snail-scheme build)
  (export build-runtime link-wasm build-wasm run-wasm run-command tool-name wasm-features
          assemble-wasm call-with-build-output)
  (import (scheme base) (scheme file) (scheme write)
          (scheme process-context) (snail-scheme compiler) (snail-scheme chromium-trace)
          (snail-scheme build-host))
  (begin
    ;; ---- Processes and owned build directories ----

    (define (tool-name variable default)
      (or (get-environment-variable variable) default))

    (define (run-command stage arguments . directory)
      ((chromium-trace stage
                       (lambda ()
                         (let ((status (process-status arguments (if (null? directory) "." (car directory))
                                                       #f (car arguments))))
                           (if (not (zero? status)) (error "build command failed" arguments status)))))))

    ;; Intermediates share the output filesystem. Publication is one rename;
    ;; protect the same inputs before any work and again after generated inputs
    ;; (such as Cargo's runtime archive) exist. Stages only write private paths.
    (define (check-build-output output inputs)
      (for-each (lambda (input)
                  (if (same-file? input output)
                      (error "output must not replace a compilation input" output input))) inputs))

    (define (call-with-build-output output inputs procedure)
      (check-build-output output inputs)
      (call-with-build-directory output
                                 (lambda (directory)
                                   (let ((finished (string-append directory "/artifact")))
                                     (procedure directory finished)
                                     (check-build-output output inputs)
                                     (publish-file finished output)))))

    ;; ---- Reusable Rust standard runtime ----

    ;; Cargo owns dependency tracking. The crate and build directory stay fixed
    ;; across Scheme programs; release LTO is configured in the root manifest.
    (define (wasm-runtime-path root)
      (string-append root "/build/wasm-runtime/wasm32-wasip1/release/snail_runtime.wasm"))

    (define build-runtime
      (chromium-trace
       "build-runtime"
       (lambda (root)
         (let* ((root (absolute-path root)) (target (string-append root "/build/wasm-runtime")))
           (run-command "build.cargo"
                        (list (tool-name "CARGO" "cargo") "rustc" "--crate-type=cdylib" "--quiet" "--offline" "--release"
                              "--target" "wasm32-wasip1" "--manifest-path" (string-append root "/Cargo.toml")
                              "--target-dir" target) root)
           (wasm-runtime-path root)))))

    ;; ---- Linking a complete Wasm program ----

    ;; Preserve the standard name section through linking and optimization:
    ;; the native backend recognizes explicit cold. function-name hints.
    (define wasm-features
      '("--mvp-features" "--enable-gc" "--enable-reference-types" "--enable-tail-call"
        "--enable-mutable-globals" "--enable-sign-ext" "--enable-bulk-memory"))

    (define entry-module
      "(module
  (import \"snail.awi\" \"snail_main\" (func $main (result eqref)))
  (import \"snail.rust\" \"_initialize\" (func $initialize))
  (func (export \"_start\") (call $initialize) (drop (call $main))))\n")

    (define (assemble-wasm input output)
      (run-command "build.assemble"
                   (append (list (tool-name "WASM_AS" "wasm-as") "-g") wasm-features
                           (list input "-o" output))))

    (define (merge-wasm scheme runtime entry output)
      (run-command "build.link"
                   (append (list (tool-name "WASM_MERGE" "wasm-merge") "-g") wasm-features
                           (list scheme "snail.awi" runtime "snail.rust" entry "snail.entry" "-o" output))))

    (define (optimize-wasm input output)
      (run-command "build.optimize"
                   (append (list (tool-name "WASM_OPT" "wasm-opt") "-g") wasm-features
                           (list "--remove-exports" "--pass-arg=remove-exports@_initialize"
                                 "-O3" "--closed-world" "--always-inline-max-function-size=40"
                                 "--converge" input "-o" output))))

    (define (link-in-directory wat runtime directory output)
      (let ((scheme (string-append directory "/scheme.wasm"))
            (entry (string-append directory "/entry.wasm"))
            (linked (string-append directory "/linked.wasm")))
        (call-with-output-file (string-append directory "/entry.wat")
          (lambda (port) (display entry-module port)))
        (assemble-wasm wat scheme)
        (assemble-wasm (string-append directory "/entry.wat") entry)
        (merge-wasm scheme runtime entry linked)
        (optimize-wasm linked output)))

    (define link-wasm
      (chromium-trace
       "link-wasm"
       (lambda (wat runtime output)
         (call-with-build-output output (list wat runtime)
                                 (lambda (directory finished)
                                   (link-in-directory wat runtime directory finished))))))

    ;; Convenience for a one-file build. Scripts building several artifacts can
    ;; build-runtime once, emit each WAT file, and call link-wasm themselves.
    (define build-wasm
      (chromium-trace
       "build-wasm"
       (lambda (root input output . options)
         (call-with-build-output output (list input (wasm-runtime-path root))
                                 (lambda (directory finished)
                                   (let ((wat (string-append directory "/program.wat")))
                                     (apply source-file->wat-file root input wat options)
                                     (link-in-directory wat (build-runtime root) directory finished)))))))

    ;; ---- Execution ----

    ;; Return the process exit code, including nonzero exits. The calling
    ;; build script decides whether execution failure is fatal or expected.
    (define (run-wasm root module arguments)
      ((chromium-trace
        "build.run"
        (lambda ()
          (let ((node (tool-name "NODE" "node")))
            (process-status (append (list node "--no-warnings"
                                          (string-append root "/scripts/run-wasi.mjs") module)
                                    arguments) "." #t node)))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (import (snail-scheme test-utils))
    (export test-build)
    (begin
      (define (test-build)
        (expect (process-status '("sh" "-c" "exit 7") "." #t "sh") 7)
        (expect (process-status '("sh" "-c" "kill -TERM $$") "." #t "sh") 143)
        (expect (guard (failure (else 'failed))
                  (run-command "test.failure" '("sh" "-c" "exit 7")) 'succeeded)
                'failed))))
   (else)))
