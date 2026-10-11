;; Native compilation has one Wasm-to-LLVM tail. Public builds own publication;
;; compile-native writes into a caller-owned workspace for composing build scripts.
(define-library (snail-scheme native)
  (export build-native compile-native native-runtime-path wasm-file->native-file run-script)
  (import (scheme base) (scheme cxr) (scheme process-context)
          (snail-scheme compiler) (snail-scheme llvm) (snail-scheme build)
          (snail-scheme build-host) (snail-scheme chromium-trace))
  (begin

    ;; ---- Wasm to native code ----

    ;; Binaryen validates and canonicalizes types before translation. Clang
    ;; optimizes the module and native host together, retaining their checks.
    ;; The Rust runtime is either linked into the Wasm input or a native archive.

    (define (collector-flags)
      (let ((include (get-environment-variable "BDWGC_INCLUDE"))
            (library (get-environment-variable "BDWGC_LIB")))
        (append '("-lgc" "-lm")
                (if include (list "-I" include) '())
                (if library (list "-L" library (string-append "-Wl,-rpath," library)) '()))))

    (define (native-in-directory root input directory output runtime)
      (let ((wasm (string-append directory "/module.wasm"))
            (llvm (string-append directory "/module.ll")))
        (run-command "native.validate"
                     (append (list (tool-name "WASM_OPT" "wasm-opt") input)
                             wasm-features (list "-q" "-g" "-o" wasm)))
        ((chromium-trace "native.translate" (lambda () (wasm-file->llvm-file wasm llvm))))
        (run-command "native.compile"
                     (append (list (tool-name "CLANG" "clang") "-O3" "-flto" "-fuse-ld=lld"
                                   llvm (string-append root "/src/native.c"))
                             (if runtime (list "-DSNAIL_NATIVE_CLI" runtime "-ldl" "-lpthread") '())
                             (collector-flags) (list "-o" output)))))

    (define wasm-file->native-file
      (chromium-trace
       "wasm-file->native-file"
       (lambda (root input output)
         (call-with-build-output output (list input)
                                 (lambda (directory staging)
                                   (native-in-directory root input directory staging #f))))))

    ;; ---- Scheme source and the native Rust runtime ----

    (define (native-runtime-path root)
      (string-append (absolute-path root) "/build/native-runtime/release/libsnail_runtime.a"))

    (define build-native-runtime
      (chromium-trace
       "build-native-runtime"
       (lambda (root)
         (run-command "build.native-runtime"
                      (list (tool-name "CARGO" "cargo") "rustc" "--quiet" "--offline" "--release"
                            "--crate-type=staticlib" "--features=native-runtime"
                            "--manifest-path" (string-append root "/Cargo.toml")
                            "--target-dir" (string-append root "/build/native-runtime")) root)
         (native-runtime-path root))))

    ;; This stage neither reserves a workspace nor publishes an artifact.
    ;; Entry #f evaluates an ordinary script; a symbol selects a zero-argument handler.
    (define (compile-native root input directory output entry libraries)
      (let ((root (absolute-path root))
            (wat (string-append directory "/program.wat"))
            (wasm (string-append directory "/program.wasm")))
        (source-file->wat-file root input wat build-host-imports libraries entry)
        (assemble-wasm wat wasm)
        (native-in-directory root wasm directory output (build-native-runtime root))))

    (define build-native
      (chromium-trace
       "build-native"
       (lambda (root input output . options)
         (if (> (length options) 2) (error "expected CLI entry and library directories"))
         (let ((entry (if (null? options) #f (car options)))
               (libraries (if (< (length options) 2) '() (cadr options))))
           (if (and entry (not (symbol? entry))) (error "expected a handler name or #f" entry))
           (call-with-build-output output (list input (native-runtime-path root))
                                   (lambda (directory finished)
                                     (compile-native root input directory finished entry libraries)))))))

    ;; ---- Ordinary script execution ----

    ;; A private executable needs no publication. The completed child status,
    ;; including nonzero, returns normally and permits workspace cleanup.
    ;; Optional library directories precede the compiler's project sources.
    (define (run-script root script arguments . options)
      (if (> (length options) 1) (error "expected library directories"))
      (call-with-build-directory #f
                                 (lambda (directory)
                                   (let ((executable (string-append directory "/script")))
                                     (compile-native root script directory executable #f
                                                     (if (null? options) '() (car options)))
                                     (process-status (cons executable arguments) "." #t script)))))))
