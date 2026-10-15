;; Compile Scheme sources, collect generated dependencies, and publish Wasm.
(define-library (snail-scheme build)
  (export build-runtime build-runtime-wat link-wasm build-wasm compile-wasm run-wasm run-script
          run-command tool-name wasm-features assemble-wasm call-with-build-output)
  (import (scheme base) (scheme file) (scheme write) (scheme process-context)
          (snail-scheme compile-build) (snail-scheme wasm-link)
          (snail-scheme build-host) (snail-scheme effects) (snail-scheme artifacts) (snail artifacts)
          (snail-scheme wasm-optimize) (snail-scheme chromium-trace)
          (only (snail-scheme wasm) write-wasm))
  (begin

    ;; ---- Source compilation and publication ----

    (define build-wasm
      (chromium-trace "build-wasm" (lambda (root input output . options)
                                     (check-binaryen-tools)
                                     (call-with-build-output output (append (list input (wasm-runtime-path root))
                                                                            (map cdr (platform-modules (current-platform))))
                                                             (lambda (directory finished)
                                                               (apply compile-wasm root input directory finished options))))))

    (define (compile-wasm root input directory output . options)
      (let ((compiled (apply source-file->compilation root input directory options)))
        (link-wasm-datum root (compilation-wasm compiled) directory output (>= (length options) 3))
        (make-artifact "program" output (compilation-artifacts compiled))))

    ;; ---- Ordinary script execution ----

    (define (run-script root script arguments . options)
      (when (> (length options) 1) (error "expected library directories"))
      (call-with-build-directory #f
                                 (lambda (directory)
                                   (let* ((program (string-append directory "/script.wasm"))
                                          (compiled (source-file->compilation root script directory build-host-imports
                                                                              (if (null? options) '() (car options)) #f)))
                                     (link-wasm-datum root (compilation-wasm compiled) directory program #t)
                                     (stage-artifacts (compilation-artifacts compiled) directory "script.wasm")
                                     (run-wasm root program arguments script)))))

    )

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
