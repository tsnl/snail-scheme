;; Integration harness for custom native hosts; normal builds use (snail-scheme native).
(import (scheme base) (scheme process-context) (snail-scheme llvm)
        (snail-scheme chromium-trace) (only (snail-scheme build-host) same-file?)
        (only (chibi filesystem) create-directory*)
        (only (chibi pathname) path-directory))
(define arguments (cdr (command-line)))
(define output (cadr arguments))
(define trace-file (string-append output ".trace.json"))
(if (or (same-file? (car arguments) trace-file) (same-file? output trace-file))
    (error "trace file must not replace build input or output" trace-file))
(create-directory* (path-directory output))
(with-chromium-trace-to trace-file
                        (chromium-trace "native.translate" (lambda () (apply wasm-file->llvm-file arguments))))
