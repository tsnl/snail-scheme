(define-library (snail-scheme native)
  (export wasm-file->native-file)
  (import (scheme base) (scheme process-context)
          (snail-scheme llvm) (snail-scheme build) (snail-scheme trace))
  (begin

    ;; ---- Native compilation of a complete linked Wasm module ----

    ;; This build operation consumes the same final binary used by a Wasm host.
    ;; Binaryen validates and canonicalizes its types; the Scheme library reads
    ;; the binary directly. Clang optimizes the module and native host
    ;; together so bounds/type helpers can inline without removing their checks.

    (define (collector-flags)
      (let ((include (get-environment-variable "BDWGC_INCLUDE"))
            (library (get-environment-variable "BDWGC_LIB")))
        (append '("-lgc" "-lm")
                (if include (list "-I" include) '())
                (if library (list "-L" library (string-append "-Wl,-rpath," library)) '()))))

    (define (native-in-directory root input directory output)
      (let ((wasm (string-append directory "/module.wasm"))
            (llvm (string-append directory "/module.ll")))
        (run-command "native.validate"
                     (append (list (tool-name "WASM_OPT" "wasm-opt") input)
                             wasm-features (list "-q" "-o" wasm)))
        (call-with-trace "native.translate" (lambda () (wasm-file->llvm-file wasm llvm)))
        (run-command "native.compile"
                     (append (list (tool-name "CLANG" "clang") "-O3" "-flto" "-fuse-ld=lld"
                                   llvm (string-append root "/src/native.c"))
                             (collector-flags) (list "-o" output)))))

    (define-traced (wasm-file->native-file root input output)
      (when (same-file? input output) (error "native output must not replace input Wasm" output))
      (call-with-build-output output
                              (lambda (directory staging)
                                (native-in-directory root input directory staging))))))
