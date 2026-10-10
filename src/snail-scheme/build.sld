;; Chibi-hosted build operations. Scripts choose inputs, outputs, and execution;
;; importing this library never reads command-line arguments or starts a build.
(define-library (snail-scheme build)
  (export build-runtime link-wasm build-wasm run-wasm run-command tool-name wasm-features
          call-with-build-output same-file?)
  (import (scheme base) (scheme cxr) (scheme file) (scheme write)
          (scheme process-context) (snail-scheme compiler) (snail-scheme trace)
          (only (chibi process) system current-process-id)
          (only (chibi pathname) path-absolute? path-normalize path-directory)
          (only (chibi filesystem) current-directory with-directory
                create-directory create-directory* delete-file-hierarchy rename-file
                file-status file-device file-inode))
  (begin
    ;; ---- Processes and owned build directories ----

    (define (tool-name variable default)
      (or (get-environment-variable variable) default))

    (define (run-command stage arguments)
      (call-with-trace stage
                       (lambda ()
                         (let ((status (command-status arguments)))
                           (if (not (zero? status))
                               (error "build command failed" arguments status))))))

    (define (command-status arguments)
      (let* ((status (cadr (system arguments))) (signal (modulo status 128)))
        (if (zero? signal) (quotient status 256) (+ 128 signal))))

    (define (absolute-path path)
      (path-normalize (if (path-absolute? path) path
                          (string-append (current-directory) "/" path))))

    (define (same-file? first second)
      (and (file-exists? first) (file-exists? second)
           (let ((a (file-status first)) (b (file-status second)))
             (and (= (file-device a) (file-device b))
                  (= (file-inode a) (file-inode b))))))

    (define (reserve-build-directory parent)
      (let ((prefix (string-append parent "/.snail-build-"
                                   (number->string (current-process-id)) "-")))
        (let loop ((serial 0))
          (if (> serial 100) (error "cannot reserve build directory" parent))
          (let ((path (string-append prefix (number->string serial))))
            (cond ((create-directory path #o700) path)
                  ((file-exists? path) (loop (+ serial 1)))
                  (else (error "cannot create build directory" path)))))))

    ;; Intermediates belong to this invocation and share the destination's
    ;; filesystem. Only a completed file is renamed over the published output.
    (define (call-with-build-directory output procedure)
      (let ((parent (path-directory (absolute-path output))))
        (if (not (create-directory* parent)) (error "cannot create output directory" parent))
        (let ((directory (reserve-build-directory parent)))
          (guard (failure (else (report-build-directory "build failed; intermediates retained: " directory)
                                (raise failure)))
            (let ((result (procedure directory)))
              (clean-build-directory directory)
              result)))))

    (define (report-build-directory message directory)
      (display message (current-error-port))
      (display directory (current-error-port))
      (newline (current-error-port)))

    ;; Publication has already succeeded. Cleanup failure must not turn that
    ;; completed build into an apparent compiler failure.
    (define (clean-build-directory directory)
      (guard (failure (else (report-build-directory "could not remove build directory: " directory)))
        (delete-file-hierarchy directory)))

    (define (call-with-build-output output procedure)
      (call-with-build-directory output
                                 (lambda (directory)
                                   (let ((finished (string-append directory "/artifact")))
                                     (procedure directory finished)
                                     (if (not (rename-file finished output))
                                         (error "cannot publish build output" output))))))

    ;; ---- Reusable Rust standard runtime ----

    ;; Cargo owns dependency tracking. The crate and build directory stay fixed
    ;; across Scheme programs; release LTO is configured in the root manifest.
    (define-traced (build-runtime root)
      (let* ((root (absolute-path root)) (target (string-append root "/build/wasm-runtime")))
        (with-directory root
                        (lambda ()
                          (run-command "build.cargo"
                                       (list (tool-name "CARGO" "cargo") "build" "--quiet" "--offline" "--release"
                                             "--target" "wasm32-wasip1" "--manifest-path" (string-append root "/Cargo.toml")
                                             "--target-dir" target))))
        (string-append target "/wasm32-wasip1/release/snail_runtime.wasm")))

    ;; ---- Linking a complete Wasm program ----

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
                   (append (list (tool-name "WASM_AS" "wasm-as")) wasm-features
                           (list input "-o" output))))

    (define (merge-wasm scheme runtime entry output)
      (run-command "build.link"
                   (append (list (tool-name "WASM_MERGE" "wasm-merge")) wasm-features
                           (list scheme "snail.awi" runtime "snail.rust" entry "snail.entry" "-o" output))))

    (define (optimize-wasm input output)
      (run-command "build.optimize"
                   (append (list (tool-name "WASM_OPT" "wasm-opt")) wasm-features
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

    (define-traced (link-wasm wat runtime output)
      (if (or (same-file? wat output) (same-file? runtime output))
          (error "output must not replace a link input" output))
      (call-with-build-output output
                              (lambda (directory finished)
                                (link-in-directory wat runtime directory finished))))

    ;; Convenience for a one-file build. Scripts building several artifacts can
    ;; build-runtime once, emit each WAT file, and call link-wasm themselves.
    (define-traced (build-wasm root input output . options)
      (if (same-file? input output) (error "output must not replace source" output))
      (call-with-build-output output
                              (lambda (directory finished)
                                (let ((wat (string-append directory "/program.wat")))
                                  (apply source-file->wat-file root input wat options)
                                  (let ((runtime (build-runtime root)))
                                    (if (same-file? runtime output) (error "output must not replace runtime" output))
                                    (link-in-directory wat runtime directory finished))))))

    ;; ---- Execution ----

    ;; Return the process exit code, including nonzero exits. The calling
    ;; build script decides whether execution failure is fatal or expected.
    (define (run-wasm root module arguments)
      (call-with-trace "build.run"
                       (lambda ()
                         (command-status (append (list (tool-name "NODE" "node") "--no-warnings"
                                                       (string-append root "/scripts/run-wasi.mjs") module)
                                                 arguments))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (import (snail-scheme test-utils))
    (export test-build)
    (begin
      (define (test-build)
        (expect (command-status '("sh" "-c" "exit 7")) 7)
        (expect (command-status '("sh" "-c" "kill -TERM $$")) 143)
        (expect (guard (failure (else 'failed))
                  (run-command "test.failure" '("sh" "-c" "exit 7")) 'succeeded)
                'failed))))
   (else)))
