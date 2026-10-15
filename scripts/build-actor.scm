;; Actor publication uses the ordinary runtime, Binaryen passes and owned builds.
(import (scheme base) (scheme cxr) (scheme file) (scheme process-context)
        (snail-scheme compiler) (snail-scheme wasm) (snail-scheme wasm-link)
        (snail-scheme wasm-optimize) (snail-scheme chromium-trace)
        (only (snail-scheme build-host) same-file?))

(define arguments (cdr (command-line)))
(define root (car arguments))
(define input (cadr arguments))
(define output (caddr arguments))
(define trace (string-append output ".trace.json"))
(when (or (string=? input output) (string=? input trace)
          (same-file? input output) (same-file? input trace))
  (error "actor build outputs must not replace the source"))
(check-binaryen-tools)

(define actor-entry
  "(module
  (import \"snail.abi\" \"actor_initialize\" (func $actor))
  (import \"snail.library\" \"_initialize\" (func $initialize))
  (import \"snail.platform\" \"environment/initialize-environment\" (func $environment))
  (func (export \"_start\") (call $initialize) (call $environment) (call $actor)))\n")

(with-chromium-trace-to
 trace
 (lambda ()
   (call-with-build-output
    output (list input (wasm-runtime-path root))
    (lambda (directory finished)
      (let ((wat (string-append directory "/actor.wat")))
        (call-with-output-file wat
          (lambda (port) (write-wasm (source-library->wasm root input) port)))
        (link-in-directory wat (build-runtime root) directory finished actor-entry))))))
