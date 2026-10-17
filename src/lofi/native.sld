;; Optional Lofi adapter: translate an exported scalar signature into the
;; native package's fixed invocation protocol. The compiler never imports this.
(define-library (lofi native)
  (export artifact->native-object)
  (import (scheme base) (scheme file) (scheme write) (only (chibi filesystem) create-directory*)
          (wasm-native) (wasm-native process) (wasm-native wasm-read)
          (wasm-native scalar-entry)
          (lofi artifact))
  (begin

    ;; ---- Wasm bytes and explicit scalar protocol metadata ----

    (define (entry-llvm artifact imports directory source)
      (let ((output (path-join directory "entry.ll"))
            (module (read-binaryen-module (path-join directory "optimized.wat")
                                          (path-join directory "entry-reader.scm"))))
        (call-with-output-file output
          (lambda (port)
            (display (read-text source) port)
            (write-native-entry module (artifact-parameters artifact) (artifact-result artifact)
                                (entry-description (artifact-entry artifact)
                                                   (artifact-parameters artifact) (artifact-result artifact))
                                (native-imports->bindings imports) port)))
        output))
    (define (artifact->native-object artifact imports directory output)
      (unless (artifact? artifact) (error "native adapter requires a Lofi Wasm artifact"))
      (create-directory* directory)
      (let ((binary (path-join directory "lofi.wasm")) (llvm (path-join directory "module.ll")))
        (write-bytes binary (artifact-bytes artifact))
        (wasm-binary->llvm binary imports directory llvm)
        (llvm-object (entry-llvm artifact imports directory llvm) output)
        output))))
