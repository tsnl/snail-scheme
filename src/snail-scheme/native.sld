;; Native compilation consumes in-memory Wasm datums. Public builds own publication;
;; compile-native writes into a caller-owned workspace for composing build scripts.
(define-library (snail-scheme native)
  (export build-native compile-native native-runtime-path run-script)
  (import (scheme base) (scheme cxr) (scheme process-context)
          (snail-scheme compile-build) (snail-scheme native-link) (snail-scheme build)
          (snail-scheme build-host) (snail-scheme chromium-trace) (snail-scheme artifacts) (snail artifacts))
  (begin

    ;; This stage neither reserves a workspace nor publishes an artifact.
    ;; Entry #f evaluates an ordinary script; a symbol selects a zero-argument handler.
    (define (compile-native root input directory output entry libraries)
      (let* ((root (absolute-path root))
             (compiled (source-file->compilation root input directory build-host-imports libraries entry)))
        (link-native root (compilation-wasm compiled) directory output)
        (make-artifact "program" output (compilation-artifacts compiled))))

    (define build-native
      (chromium-trace "build-native" (lambda (root input output . options)
                                       (if (> (length options) 3) (error "expected CLI entry, library directories, and artifact dependencies"))
                                       (let ((entry (if (null? options) #f (car options)))
                                             (libraries (if (< (length options) 2) '() (cadr options)))
                                             (dependencies (if (< (length options) 3) '() (caddr options))))
                                         (if (and entry (not (symbol? entry))) (error "expected a handler name or #f" entry))
                                         (call-with-build-output output (list input (native-runtime-path root))
                                                                 (lambda (directory finished)
                                                                   (compile-native root input directory finished entry libraries)) dependencies)))))

    ;; ---- Ordinary script execution ----

    ;; A private executable needs no publication. The completed child status,
    ;; including nonzero, returns normally and permits workspace cleanup.
    ;; Optional library directories precede the compiler's project sources.
    (define (run-script root script arguments . options)
      (if (> (length options) 1) (error "expected library directories"))
      (call-with-build-directory #f
                                 (lambda (directory)
                                   (let* ((executable (string-append directory "/script"))
                                          (compiled (compile-native root script directory executable #f
                                                                    (if (null? options) '() (car options))))
                                          (runtime (find-artifact "snail-runtime.wat"))
                                          (dependencies (artifact-dependencies compiled)))
                                     (stage-artifacts
                                      (if (or (not runtime) (assoc "snail-runtime.wat"
                                                                   (map (lambda (artifact) (cons (artifact-name artifact) artifact))
                                                                        (artifact-closure dependencies))))
                                          dependencies
                                          (cons (make-artifact "snail-runtime.wat" runtime '()) dependencies))
                                      directory "script")
                                     (process-status (cons executable arguments) "." #t script)))))))
