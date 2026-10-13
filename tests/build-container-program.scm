;; Independent linked-Wasm boundary fixtures; no instrumentation changes the IR.
(import (scheme base) (scheme process-context) (snail-scheme build)
        (snail-scheme compiler) (snail-scheme chromium-trace) (snail-scheme wasm-storage))
(define arguments (cdr (command-line)))
(define root (car arguments))
(define output (list-ref arguments 2))
(with-chromium-trace-to
 (string-append output ".trace.json")
 (lambda ()
   (parameterize ((storage-optimizations-enabled
                   (or (< (length arguments) 4) (not (equal? (list-ref arguments 3) "off")))))
     (source-file->wat-file root (cadr arguments) (string-append output ".wat")
                            '((container-exchange! . "snail.test")
                              (container-envelope . "snail.test")
                              (container-call . "snail.test")
                              (container-pair-exchange! . "snail.test"))))
   (link-wasm (string-append output ".wat") (build-runtime root) output)))
