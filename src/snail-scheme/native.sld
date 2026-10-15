;; Optimize program Wasm with Binaryen, then mechanically lower it to LLVM.
;; Native links the Rust archive; Wasm links the scalar provider's Wasm.
(define-library (snail-scheme native)
  (export native-wasm->llvm native-binary->llvm)
  (import (scheme base) (scheme cxr) (scheme file)
          (snail-scheme wasm) (snail-scheme wasm-read) (snail-scheme wasm-optimize)
          (snail-scheme llvm) (snail-scheme build-host))
  (begin

    ;; ---- Shared Wasm optimization ----

    (define (native-binary->llvm input directory output)
      (check-binaryen-tools)
      (let ((optimized (string-append directory "/optimized.wasm"))
            (text (string-append directory "/optimized.wat"))
            (reader (string-append directory "/reader.scm")))
        (optimize-scheme-wasm input optimized)
        (run-command "native.disassemble"
                     (list (tool-name "WASM_DIS" "wasm-dis") optimized "-o" text))
        (wasm->llvm-file (read-binaryen-module text reader) output)))

    (define (native-wasm->llvm datum directory output)
      (let ((text (string-append directory "/source.wat"))
            (binary (string-append directory "/source.wasm")))
        (check-binaryen-tools)
        (call-with-output-file text (lambda (port) (write-wasm datum port)))
        (assemble-wasm text binary)
        (native-binary->llvm binary directory output)))))
