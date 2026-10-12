;; Build-stage compilation owns generator processes and deployment dependencies.
;; The portable compiler only calls the installed library-generator resolver.
(define-library (snail-scheme compile-build)
  (export source-file->compilation compilation-wasm compilation-artifacts)
  (import (scheme base) (scheme cxr) (scheme file) (scheme write)
          (snail-scheme compiler) (snail-scheme chromium-trace) (snail-scheme syntax)
          (snail-scheme build-host) (snail-scheme artifacts)
          (snail-scheme generation) (snail-scheme wasm-link))
  (begin

    ;; ---- Compilation results and dependency ownership ----

    (define-record-type <compilation>
      (make-compilation wasm artifacts) compilation?
      (wasm compilation-wasm) (artifacts compilation-artifacts))

    ;; Cache results for one build only. Every nested compilation has its own
    ;; artifact accumulator, including when a shared generator is already cached.
    (define (collect-compilation thunk)
      (let ((dependencies '()))
        (parameterize ((library-generator
                        (lambda (root path wrapper directories)
                          (let ((result (prepare-generator root path wrapper directories)))
                            (set! dependencies (append dependencies (cdr result)))
                            (car result)))))
          (let ((wasm (thunk))) (make-compilation wasm dependencies)))))

    ;; The caller retains directory until it publishes or copies the artifacts.
    (define source-file->compilation
      (chromium-trace
       "source-file->compilation"
       (lambda (root input directory . options)
         (when (> (length options) 3) (error "expected foreign declarations, library directories, and CLI entry"))
         (parameterize ((generation-session (or (generation-session) (make-generation-session directory '() 0))))
           (collect-compilation
            (lambda ()
              (source-file->wasm (absolute-path root) input
                                 (if (null? options) '() (car options))
                                 (if (< (length options) 2) '() (map absolute-library-directory (cadr options)))
                                 (if (= (length options) 3) (caddr options) #f))))))))

    ;; The CLI accepts an empty -I directory as the current working directory.
    (define (absolute-library-directory directory)
      (absolute-path (if (string=? directory "") "." directory)))

    ;; ---- Generator execution and session ownership ----

    (define-record-type <generation-session>
      (make-generation-session directory cache serial) generation-session?
      (directory session-directory) (cache session-cache set-session-cache!)
      (serial session-serial set-session-serial!))
    (define generation-session (make-parameter #f))

    (define (generator-directory)
      (let* ((session (generation-session)) (serial (+ 1 (session-serial session)))
             (directory (string-append (session-directory session) "/generator-" (number->string serial))))
        (set-session-serial! session serial)
        (create-directory* directory)
        (absolute-path directory)))

    (define (source-directory path)
      (let loop ((index (- (string-length path) 1)))
        (if (char=? (string-ref path index) #\/) (substring path 0 (+ index 1))
            (loop (- index 1)))))

    (define (cached-generation path)
      (let loop ((entries (session-cache (generation-session))))
        (cond ((null? entries) #f)
              ((or (equal? path (caar entries)) (same-file? path (caar entries))) (car entries))
              (else (loop (cdr entries))))))

    (define (prepare-generator root path wrapper directories)
      (let ((prior (cached-generation path)))
        (if prior
            (or (cdr prior) (error "generate-library dependency cycle" path))
            (let* ((session (generation-session)) (entry (cons path #f)))
              (set-session-cache! session (cons entry (session-cache session)))
              (let ((result (execute-generator root path wrapper directories)))
                (set-cdr! entry result)
                result)))))

    (define (execute-generator root path wrapper directories)
      (let* ((directory (generator-directory)) (output (string-append directory "/result.scm"))
             (program (string-append directory "/program.wasm")) (source (source-directory path))
             (forms (generator-program wrapper output source directory))
             (compiled (collect-compilation
                        (lambda () (syntax-list->wasm root forms build-host-imports directories #f)))))
        (call-with-output-file (string-append directory "/generator.scm")
          (lambda (port) (for-each (lambda (form) (write (syntax->datum form) port) (newline port)) forms)))
        (link-wasm-datum root (compilation-wasm compiled) directory program)
        (stage-artifacts (compilation-artifacts compiled) directory "program.wasm")
        (run-command "build.generate-library"
                     (list "env" (string-append "SNAIL_ARTIFACT_ROOT=" directory "/artifacts")
                           (tool-name "NODE" "node") "--no-warnings"
                           (string-append root "/scripts/run-wasi.mjs") program) source)
        (let* ((result (syntax->datum (read-library-form output)))
               (form (generated-library-form wrapper result))
               (artifacts (snapshot-artifacts (decode-generation-artifacts result)
                                              (string-append directory "/snapshot"))))
          (cons form artifacts))))

    ))
