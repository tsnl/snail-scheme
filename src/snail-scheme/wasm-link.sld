;; Host-independent build operations. Scripts choose inputs, outputs, and execution;
;; importing this library never reads command-line arguments or starts a build.
(define-library (snail-scheme wasm-link)
  (export build-runtime build-runtime-wat link-wasm link-wasm-datum link-in-directory wasm-runtime-path run-wasm run-command tool-name wasm-features
          assemble-wasm call-with-build-output)
  (import (scheme base) (scheme file) (scheme write)
          (scheme process-context) (snail-scheme chromium-trace)
          (snail-scheme build-host) (snail-scheme artifacts) (snail artifacts)
          (snail-scheme wasm-optimize) (snail-scheme effects)
          (only (snail-scheme wasm) write-wasm))
  (begin
    ;; ---- Processes and owned build directories ----

    ;; Intermediates share the output filesystem. Publication is one rename;
    ;; protect the same inputs before any work and again after generated inputs
    ;; (such as Cargo's runtime archive) exist. Stages only write private paths.
    (define (check-build-output output inputs)
      (for-each (lambda (input)
                  (if (same-file? input output)
                      (error "output must not replace a compilation input" output input))) inputs))

    (define (call-with-build-output output inputs procedure . dependencies)
      (let* ((dependencies (if (null? dependencies) '() (car dependencies)))
             (inputs (append inputs (apply append (map artifact-inputs (artifact-closure dependencies))))))
        (check-build-output output inputs)
        (call-with-build-directory output
                                   (lambda (directory)
                                     (let* ((finished (string-append directory "/artifact"))
                                            (result (procedure directory finished))
                                            (dependencies (append dependencies (if (artifact? result) (artifact-dependencies result) '()))))
                                       (when (and (artifact? result) (not (same-file? finished (artifact-source result))))
                                         (error "build result must name the completed candidate" (artifact-source result) finished))
                                       (check-build-output output (append inputs (apply append (map artifact-inputs (artifact-closure dependencies)))))
                                       (if (null? dependencies) (publish-file finished output)
                                           (let ((bundle (string-append directory "/bundle")))
                                             (create-directory* bundle)
                                             (publish-file finished (string-append bundle "/program"))
                                             (stage-artifacts dependencies bundle "program")
                                             (publish-bundle bundle output))))))))

    ;; ---- Reusable Rust standard runtime ----

    ;; Cargo owns dependency tracking. The crate and build directory stay fixed
    ;; across Scheme programs; release LTO is configured in the root manifest.
    (define (wasm-runtime-path root)
      (string-append root "/build/wasm-runtime/wasm32-wasip1/release/snail_runtime.wasm"))

    (define build-runtime
      (chromium-trace "build-runtime" (lambda (root)
                                        (or (find-artifact "snail-runtime.wat") (compile-runtime root)))))

    (define compile-runtime
      (chromium-trace "compile-runtime" (lambda (root)
                                          (let* ((root (absolute-path root)) (target (string-append root "/build/wasm-runtime")))
                                            (run-command "build.cargo"
                                                         (list (tool-name "CARGO" "cargo") "rustc" "--crate-type=cdylib" "--quiet" "--offline" "--release"
                                                               "--target" "wasm32-wasip1" "--manifest-path" (string-append root "/Cargo.toml")
                                                               "--target-dir" target) root)
                                            (wasm-runtime-path root)))))

    ;; Cargo emits Wasm; Binaryen converts it into the distributable WAT file.
    ;; This explicit producer always checks Cargo's inputs, even in an installed
    ;; compiler that already carries a runtime from its own build.
    (define (build-runtime-wat root output)
      (let ((runtime (compile-runtime root)))
        (call-with-build-output output (list runtime)
                                (lambda (directory finished)
                                  (run-command "build.runtime-wat"
                                               (list (tool-name "WASM_DIS" "wasm-dis") runtime "-o" finished))))
        (absolute-path output)))

    ;; ---- Linking a complete Wasm program ----

    ;; Preserve the standard name section for Wasm inspection and profiling.
    ;; Optimize the Scheme module before linking its library and selected platform.

    (define script-entry-module
      "(module
  (import \"snail.abi\" \"snail_main\" (func $main (result eqref)))
  (import \"snail.library\" \"_initialize\" (func $initialize))
  (import \"snail.platform\" \"environment/initialize-environment\" (func $environment))
  (func (export \"_start\") (call $initialize) (call $environment) (drop (call $main))))\n")

    (define command-entry-module
      "(module
  (import \"snail.abi\" \"snail:main\" (func $main (param i32) (result i32)))
  (import \"snail.abi\" \"vector_new\" (func $slots (param i32) (result i32)))
  (import \"snail.abi\" \"release\" (func $release (param i32)))
  (import \"snail.abi\" \"kind\" (func $kind (param i32) (result i32)))
  (import \"snail.abi\" \"as_integer\" (func $integer (param i32) (result i64)))
  (import \"snail.library\" \"_initialize\" (func $initialize))
  (import \"snail.platform\" \"environment/initialize-environment\" (func $environment))
  (import \"snail.platform\" \"diagnostics/fail\" (func $fail (param i32) (result i32)))
  (import \"wasi_snapshot_preview1\" \"proc_exit\" (func $exit (param i32)))
  (func (export \"_start\") (local $args i32) (local $result i32) (local $status i64)
    (call $initialize) (call $environment)
    (local.set $args (call $slots (i32.const 0)))
    (local.set $result (call $main (local.get $args)))
    (if (i32.ne (call $kind (local.get $result)) (i32.const 4))
      (then (drop (call $fail (i32.const 10)))))
    (local.set $status (call $integer (local.get $result)))
    (call $release (local.get $result)) (call $release (local.get $args))
    (if (i32.or (i64.lt_s (local.get $status) (i64.const 0))
                (i64.gt_s (local.get $status) (i64.const 255)))
      (then (drop (call $fail (i32.const 10)))))
    (call $exit (i32.wrap_i64 (local.get $status)))))\n")

    (define (merge-wasm scheme runtime entry platform output)
      (run-command "build.link"
                   (append (list (tool-name "WASM_MERGE" "wasm-merge") "-g") wasm-features
                           (list scheme "snail.abi" runtime "snail.library" platform "snail.platform"
                                 entry "snail.entry")
                           (apply append (map (lambda (module) (list (cdr module) (car module)))
                                              (platform-modules (current-platform))))
                           (list "-o" output))))

    (define (optimize-wasm input output)
      (run-command "build.optimize"
                   (append (list (tool-name "WASM_OPT" "wasm-opt") "-g") wasm-features
                           (list "--remove-exports"
                                 (string-append "--pass-arg=remove-exports@_initialize"
                                                (apply string-append
                                                       (map (lambda (name) (string-append "," name))
                                                            (implementation-exports (current-platform)))))
                                 "-O3" "--closed-world" "--always-inline-max-function-size=40"
                                 "--converge" input "-o" output))))

    (define (link-in-directory wat runtime directory output . entry-options)
      (validate-platform (current-platform))
      (let ((scheme (string-append directory "/scheme.wasm"))
            (optimized (string-append directory "/scheme.optimized.wasm"))
            (entry (string-append directory "/entry.wasm"))
            (platform (string-append directory "/platform.wasm"))
            (linked (string-append directory "/linked.wasm")))
        (call-with-output-file (string-append directory "/entry.wat")
          (lambda (port) (display (if (and (pair? entry-options) (car entry-options))
                                      command-entry-module script-entry-module) port)))
        (call-with-output-file (string-append directory "/platform.wat")
          (lambda (port) (write-wasm (platform-module (current-platform)) port)))
        (assemble-wasm wat scheme)
        (assemble-wasm (string-append directory "/entry.wat") entry)
        (assemble-wasm (string-append directory "/platform.wat") platform)
        (optimize-scheme-wasm scheme optimized)
        (merge-wasm optimized runtime entry platform linked)
        (optimize-wasm linked output)))

    (define link-wasm
      (chromium-trace
       "link-wasm"
       (lambda (wat runtime output)
         (check-binaryen-tools)
         (call-with-build-output output (append (list wat runtime) (map cdr (platform-modules (current-platform))))
                                 (lambda (directory finished)
                                   (link-in-directory wat runtime directory finished))))))

    (define (link-wasm-datum root datum directory output . entry-options)
      (let ((wat (string-append directory "/program.wat")))
        (call-with-output-file wat (lambda (port) (write-wasm datum port)))
        (apply link-in-directory wat (build-runtime root) directory output entry-options)))

    ;; ---- Execution ----

    ;; Return the process exit code, including nonzero exits. The calling
    ;; build script decides whether execution failure is fatal or expected.
    (define (run-wasm root module arguments . identity)
      ((chromium-trace
        "build.run"
        (lambda ()
          (let ((node (tool-name "NODE" "node")))
            (process-status (append (list node "--no-warnings"
                                          (string-append root "/scripts/run-wasi.mjs"))
                                    (if (null? identity) '() (list "--identity" (car identity)))
                                    (list module)
                                    arguments) "." #t node))))))

    ))
