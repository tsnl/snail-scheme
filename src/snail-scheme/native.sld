;; Both backends consume shared optimized program Wasm; their linked providers
;; differ. Native links the Rust archive; Wasm merges provider Wasm and optimizes.
;; Binaryen owns Wasm optimization; LLVM only lowers its typed operations.
(define-library (snail-scheme native)
  (export native-wasm->llvm native-binary->llvm native-platform-bindings)
  (import (scheme base) (scheme cxr) (scheme file)
          (snail-scheme wasm) (snail-scheme wasm-read) (snail-scheme wasm-optimize)
          (snail-scheme llvm) (snail-scheme build-host) (snail-scheme effects))
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
        (native-binary->llvm binary directory output)))

    ;; ---- Selected platform aliases ----

    ;; Effect names resolve to the selected provider before lowering. A provider
    ;; still needs an authoritative C signature; absent bindings remain errors.
    (define (handler-native-bindings handler bindings)
      (let ((interface (handler-interface handler)))
        (map (lambda (operation)
               (let* ((name (cdr (assq (operation-name operation) (handler-bindings handler))))
                      (entry (assoc (list (handler-module handler) name) bindings)))
                 (and entry (cons (list "snail.platform" (operation-export interface operation))
                                  (cdr entry)))))
             (effect-operations interface))))

    (define (native-platform-bindings bindings)
      (let loop ((rest (apply append (map (lambda (handler) (handler-native-bindings handler bindings))
                                          (platform-handlers (current-platform)))))
                 (result bindings))
        (cond ((null? rest) result)
              ((car rest) (loop (cdr rest) (cons (car rest) result)))
              (else (loop (cdr rest) result)))))))
