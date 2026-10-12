;; Bootstrap from the checkout, then rebuild using the resulting executable:
;;   chibi-scheme -h512M -I src build.scm
;;   node scripts/run-wasi.mjs build/snail-scheme.wasm -Isrc build.scm
;; An optional argument selects the complete output filename.
(import (scheme base) (scheme file) (scheme write) (scheme process-context)
        (snail-scheme build) (snail-scheme build-host)
        (snail-scheme chromium-trace))

(define arguments (cdr (command-line)))
(if (> (length arguments) 1) (error "usage: build.scm [OUTPUT]"))
(define output (if (null? arguments) "build/snail-scheme.wasm" (car arguments)))
(define trace-file (string-append output ".trace.json"))
(define root (absolute-path "."))
(define source (string-append root "/main.scm"))
(if (or (same-file? source trace-file) (same-file? output trace-file))
    (error "trace file must not replace build input or output" trace-file))

;; Installation data belongs to this build, alongside its compiler intermediates.
(define (write-installation directory)
  (create-directory* (string-append directory "/snail-scheme"))
  (call-with-output-file (string-append directory "/snail-scheme/installation.sld")
    (lambda (port)
      (write `(define-library (snail-scheme installation)
                (export installation-root) (import (scheme base))
                (begin (define installation-root ,root))) port))))

(define (output-directory output)
  (let ((path (absolute-path output)))
    (let loop ((index (- (string-length path) 1)))
      (if (char=? (string-ref path index) #\/) (substring path 0 (+ index 1))
          (loop (- index 1))))))

(create-directory* (output-directory output))
(with-chromium-trace-to trace-file
                        (lambda ()
                          (call-with-build-output output (list source)
                                                  (lambda (directory artifact)
                                                    (write-installation directory)
                                                    (compile-wasm root source directory artifact build-host-imports (list directory) 'main)))))
