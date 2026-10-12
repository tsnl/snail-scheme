;; The host executable toolchain consumes a completed Wasm datum. It knows no
;; Scheme source or library loader, so generators can use it during compilation.
(define-library (snail-scheme native-link)
  (export link-native native-runtime-path)
  (import (scheme base) (scheme process-context) (snail-scheme llvm)
          (snail-scheme build-host) (snail-scheme chromium-trace)
          (snail-scheme wasm-optimize))
  (begin

    ;; ---- Wasm to native code ----

    ;; Name/type resolution feeds LLVM directly. Clang optimizes and links the
    ;; generated module, native host and Rust archive, retaining their checks.

    (define (collector-flags)
      (let ((include (get-environment-variable "BDWGC_INCLUDE"))
            (library (get-environment-variable "BDWGC_LIB")))
        (append '("-lgc" "-lm")
                (if include (list "-I" include) '())
                (if library (list "-L" library (string-append "-Wl,-rpath," library)) '()))))

    (define (link-native root datum directory output)
      (let ((llvm (string-append directory "/module.ll")) (runtime (build-native-runtime root)))
        (let ((prepared (prepare-native-wasm datum directory)))
          ((chromium-trace "native.translate" (lambda () (wasm->llvm-file prepared llvm)))))
        (run-command "native.compile"
                     (append (list (tool-name "CLANG" "clang") "-O3" "-flto"
                                   (string-append "-fuse-ld=" (tool-name "LLD" "lld"))
                                   llvm (string-append root "/src/native.c"))
                             (list runtime "-ldl" "-lpthread")
                             (collector-flags) (list "-o" output)))))

    ;; ---- Scheme source and the native Rust runtime ----

    (define (native-runtime-path root)
      (string-append (absolute-path root) "/build/native-runtime/release/libsnail_runtime.a"))

    (define build-native-runtime
      (chromium-trace "build-native-runtime" (lambda (root)
                                               (run-command "build.native-runtime"
                                                            (list (tool-name "CARGO" "cargo") "rustc" "--quiet" "--offline" "--release"
                                                                  "--crate-type=staticlib" "--features=native-runtime"
                                                                  "--manifest-path" (string-append root "/Cargo.toml")
                                                                  "--target-dir" (string-append root "/build/native-runtime")) root)
                                               (native-runtime-path root))))

    ))
