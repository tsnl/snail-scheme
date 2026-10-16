;; Public boundary: Wasm bytes and declared physical imports enter native lowering.
(define-library (wasm-native)
  (export make-native-import native-import? native-imports->bindings
          wasm-binary->llvm llvm-object link-native-object
          rust-bindings runtime-bindings check-provider-bindings
          native-cargo-environment native-system-environment ensure-native-supervisor
          rust-source-inputs source-hashes check-stable-inputs native-evidence)
  (import (scheme base) (chibi filesystem)
          (wasm-native native) (wasm-native native-build)
          (only (wasm-native llvm) current-native-imports)
          (only (wasm-native chromium-trace) with-chromium-trace-to))
  (begin

    ;; ---- Checked physical import declarations ----

    (define-record-type <native-import>
      (new-native-import key symbol parameters results) native-import?
      (key native-import-key) (symbol native-import-symbol)
      (parameters native-import-parameters) (results native-import-results))
    (define (physical-scalars? types)
      (and (list? types)
           (let visit ((types types))
             (or (null? types)
                 (and (memq (car types) '(i32 i64 f32 f64)) (visit (cdr types)))))))
    (define (make-native-import module name symbol parameters result)
      (unless (and (string? module) (string? name) (string? symbol)
                   (physical-scalars? parameters)
                   (or (eq? result 'void) (physical-scalars? (list result))))
        (error "native import requires strings, scalar parameters and a scalar or void result"))
      (new-native-import (list module name) symbol (append parameters '())
                         (if (eq? result 'void) '() (list result))))
    (define (native-imports->bindings imports)
      (unless (list? imports) (error "native imports require a list of native import values"))
      (let visit ((imports imports) (bindings '()))
        (if (null? imports) (reverse bindings)
            (let ((entry (car imports)))
              (unless (native-import? entry) (error "expected a native import value" entry))
              (when (assoc (native-import-key entry) bindings)
                (error "duplicate native import" (native-import-key entry)))
              (visit (cdr imports)
                     (cons (list (native-import-key entry) (native-import-symbol entry)
                                 (native-import-parameters entry) (native-import-results entry)) bindings))))))

    ;; ---- Mandatory Binaryen then mechanical LLVM lowering ----

    (define (wasm-binary->llvm input imports directory output)
      (let ((bindings (native-imports->bindings imports)))
        (create-directory* directory)
        (with-chromium-trace-to
         (string-append directory "/native.trace.json")
         (lambda ()
           (parameterize ((current-native-imports bindings))
             (native-binary->llvm input directory output))))
        output)))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-wasm-native)
    (import (wasm-native test-utils))
    (begin
      (define (import-error thunk)
        (guard (failure (else (and (error-object? failure) (error-object-message failure))))
          (thunk) #f))
      (define (test-wasm-native)
        (let ((entry (make-native-import "host" "read" "host_read" '(i32 f64) 'i64)))
          (expect (native-import? entry) #t)
          (expect (native-imports->bindings (list entry)) '((("host" "read") "host_read" (i32 f64) (i64))))
          (expect (native-imports->bindings '()) '())
          (expect (import-error (lambda () (native-imports->bindings (list entry entry)))) "duplicate native import")
          (expect (import-error (lambda () (native-imports->bindings '(unparsed)))) "expected a native import value")
          (expect (import-error (lambda () (make-native-import "host" "read" "host_read" '(Bool) 'i64)))
                  "native import requires strings, scalar parameters and a scalar or void result")))))
   (else)))
