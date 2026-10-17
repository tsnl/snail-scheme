;; Optimize program Wasm with Binaryen, then mechanically lower it to LLVM.
;; Native links the shared Rust crate; Wasm links that crate's Wasm artifact.
(define-library (wasm-native native)
  (export native-wasm->llvm native-binary->llvm)
  (import
   (scheme base)
   (scheme cxr)
   (scheme file)
   (wasm-native wasm)
   (wasm-native wasm-read)
   (wasm-native wasm-optimize)
   (wasm-native llvm)
   (wasm-native build-host))
  (begin

    ;; ---- Shared Wasm optimization ----

    (define (native-binary->llvm input directory output)
      (check-binaryen-tools '(("WASM_OPT" . "wasm-opt") ("WASM_DIS" . "wasm-dis")))
      (let ((optimized (string-append directory "/optimized.wasm"))
            (text (string-append directory "/optimized.wat"))
            (reader (string-append directory "/reader.scm")))
        (optimize-wasm input optimized)
        (run-command "native.disassemble"
                     (list (tool-name "WASM_DIS" "wasm-dis") optimized "-o" text))
        (wasm->llvm-file (read-binaryen-module text reader) output)))

    (define (native-wasm->llvm datum directory output)
      (let ((text (string-append directory "/source.wat"))
            (binary (string-append directory "/source.wasm")))
        (check-binaryen-tools '(("WASM_AS" . "wasm-as")))
        (call-with-output-file text (lambda (port) (write-wasm datum port)))
        (assemble-wasm text binary)
        (native-binary->llvm binary directory output)))))
