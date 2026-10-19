;; Small OS/Rust operations used by Scheme tools, built independently of the runtime.
(define-library (lofi compiler tools host-tools)
  (export build-host-tool)
  (import
   (scheme base)
   (chibi filesystem)
   (lofi host process))
  (begin

    ;; ---- Cargo-built host capabilities ----

    (define (build-host-tool root name)
      (let ((target (path-join root "build/host-tools")))
        (create-directory* target)
        (run-command! (list (tool-name "CARGO" "cargo") "build" "--quiet" "--offline" "--release"
                            "--manifest-path" (path-join root "tools/host/Cargo.toml")
                            "--target-dir" target "--bin" name)
                      '((supervisor . #f)))
        (path-join target "release" name)))))
