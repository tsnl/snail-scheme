(define-library (snail-scheme native)
  (export wasm-file->native-file)
  (import (scheme base) (scheme process-context)
          (snail-scheme llvm) (snail-scheme build) (snail-scheme trace))
  (begin

    ;; ---- Native compilation of a complete linked Wasm module ----

    ;; This build operation consumes the same final binary used by a Wasm host.
    ;; Binaryen validates and disassembles it; the Scheme library translates the
    ;; resulting folded expressions. Clang optimizes the module and native host
    ;; together so bounds/type helpers can inline without removing their checks.

    (define (collector-flags)
      (let ((include (get-environment-variable "BDWGC_INCLUDE"))
            (library (get-environment-variable "BDWGC_LIB")))
        (append '("-lgc" "-lm")
                (if include (list "-I" include) '())
                (if library (list "-L" library (string-append "-Wl,-rpath," library)) '()))))

    (define (native-in-directory root input directory output)
      (let ((wat (string-append directory "/module.wat"))
            (llvm (string-append directory "/module.ll")))
        (run-command "native.decode" (list (tool-name "WASM_DIS" "wasm-dis") input "-o" wat))
        (call-with-trace "native.translate" (lambda () (wat-file->llvm-file wat llvm)))
        (run-command "native.compile"
                     (append (list (tool-name "CLANG" "clang") "-O3" "-flto" "-fuse-ld=lld"
                                   llvm (string-append root "/src/native.c"))
                             (collector-flags) (list "-o" output)))))

    (define-traced (wasm-file->native-file root input output)
      (when (same-file? input output) (error "native output must not replace input Wasm" output))
      (call-with-build-output output
                              (lambda (directory staging)
                                (native-in-directory root input directory staging))))))
