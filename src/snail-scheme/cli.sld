;; Build and run the native CLI platform. Scheme goes through Wasm and LLVM;
;; its imported runtime operations link directly to the native Rust library.
(define-library (snail-scheme cli)
  (export build-native build-interpreter run-script)
  (import (scheme base) (scheme cxr) (scheme file) (scheme write)
          (snail-scheme compiler) (snail-scheme build) (snail-scheme build-host)
          (snail-scheme native) (snail-scheme trace))
  (begin
    ;; ---- Reusable native Rust runtime ----

    (define-traced (build-native-runtime root)
      (let ((target (string-append root "/build/native-runtime")))
        (run-command "build.native-runtime"
                     (list (tool-name "CARGO" "cargo") "rustc" "--quiet" "--offline" "--release"
                           "--crate-type=staticlib" "--features=native-runtime"
                           "--manifest-path" (string-append root "/Cargo.toml") "--target-dir" target) root)
        (string-append target "/release/libsnail_runtime.a")))

    ;; ---- Scheme source to a native command ----

    ;; Entry #f means an ordinary script. A symbol selects a zero-argument
    ;; handler defined by the source module; its result is the process status.
    (define (check-native-output root input output)
      (if (or (same-file? input output)
              (same-file? (string-append root "/build/native-runtime/release/libsnail_runtime.a") output))
          (error "output must not replace a compilation input" output)))

    (define (native-in-directory root input directory output entry libraries)
      (let ((wat (string-append directory "/program.wat"))
            (wasm (string-append directory "/program.wasm")))
        (source-file->wat-file root input wat build-host-imports libraries entry)
        (run-command "build.assemble"
                     (append (list (tool-name "WASM_AS" "wasm-as")) wasm-features (list wat "-o" wasm)))
        (wasm-file->native-file root wasm output (build-native-runtime root))))

    (define-traced (build-native root input output . options)
      (if (> (length options) 2) (error "expected CLI entry and library directories"))
      (check-native-output root input output)
      (let ((root (absolute-path root)) (input (absolute-path input))
            (entry (if (null? options) #f (car options)))
            (libraries (if (< (length options) 2) '() (cadr options))))
        (if (and entry (not (symbol? entry))) (error "expected a handler name or #f" entry))
        (call-with-build-output output
                                (lambda (directory finished)
                                  (native-in-directory root input directory finished entry libraries)
                                  ;; Cargo may have created the runtime since the first check.
                                  (check-native-output root input output)))))

    ;; ---- The interpreter builds itself ----

    (define (write-installation root directory)
      (create-directory* (string-append directory "/snail-scheme"))
      (call-with-output-file (string-append directory "/snail-scheme/installation.sld")
        (lambda (port)
          (write `(define-library (snail-scheme installation)
                    (export installation-root) (import (scheme base))
                    (begin (define installation-root ,root))) port))))

    (define (build-interpreter root output)
      (let ((root (absolute-path root)))
        (check-native-output root (string-append root "/main.scm") output)
        (call-with-build-output output
                                (lambda (directory finished)
                                  (write-installation root directory)
                                  (native-in-directory root (string-append root "/main.scm") directory finished
                                                       'main (list directory))
                                  (check-native-output root (string-append root "/main.scm") output)))))

    ;; The child receives the script's name as argv[0], literal user arguments,
    ;; and untouched stdin. A nonzero child status still permits normal cleanup.
    (define (run-script root script arguments)
      (call-with-build-directory #f
                                 (lambda (directory)
                                   (let ((executable (string-append directory "/script")))
                                     (build-native root script executable)
                                     (process-status (cons executable arguments) "." #t script)))))))
