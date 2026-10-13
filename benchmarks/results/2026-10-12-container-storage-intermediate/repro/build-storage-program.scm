;; Keep raw WAT beside each linked artifact so the test checks physical storage.
(import (scheme base) (scheme cxr) (scheme process-context)
        (snail-scheme compiler) (snail-scheme build) (snail-scheme chromium-trace)
        (snail-scheme wasm-storage))
(define arguments (cdr (command-line)))
(define root (car arguments))
(define source (cadr arguments))
(define output (caddr arguments))
(storage-optimizations-enabled (not (string=? (cadddr arguments) "off")))
(with-chromium-trace-to
 (string-append output ".trace.json")
 (lambda ()
   (source-file->wat-file root source (string-append output ".wat") '())
   (link-wasm (string-append output ".wat") (build-runtime root) (string-append output ".wasm"))))
