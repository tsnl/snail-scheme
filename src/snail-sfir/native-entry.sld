;; The native process adapter calls one fixed ABI, never a caller-chosen cast.
;; Construct it from checked scalar metadata and the actual optimized Wasm types.
(define-library (snail-sfir native-entry)
  (export write-native-entry)
  (import (scheme base) (scheme cxr)
          (only (snail-tools json) json->string)
          (snail-scheme wasm-resolve) (snail-scheme llvmlite))
  (begin

    ;; ---- Actual function signatures ----

    (define (physical-type type)
      (case type
        ((I32 Bool Char) 'i32) ((I64) 'i64) ((F32) 'f32) ((F64) 'f64)
        (else (error "native execution entry requires scalar parameters and a scalar or Unit result" type))))
    (define (result-types result)
      (if (eq? result 'Unit) '() (list (physical-type result))))
    (define (declarations nodes tag)
      (let visit ((nodes nodes) (found '()))
        (cond ((null? nodes) (reverse found))
              ((eq? (caar nodes) tag) (visit (cdr nodes) (cons (car nodes) found)))
              (else (visit (cdr nodes) found)))))
    (define (indexed nodes tag index)
      (let ((entry (assv index (map cdr (declarations nodes tag)))))
        (unless entry (error "native entry is missing a resolved declaration" tag index))
        entry))
    (define (export-signature nodes name)
      (let ((entry (assoc name (map cdr (declarations nodes 'export)))))
        (unless (and entry (eq? (caadr entry) 'func))
          (error "native execution requires a function export" name))
        (let* ((function (indexed nodes 'func (cadadr entry)))
               (type (indexed nodes 'type (cadr function))))
          (cadr type))))
    (define (check-entry nodes parameters result)
      (when (pair? (declarations nodes 'start))
        (error "native execution artifact must not have an automatic start function"))
      (unless (equal? (export-signature nodes "main") '(func () ()))
        (error "native initializer signature must be () -> Unit"))
      (unless (equal? (export-signature nodes "entry")
                      (list 'func (map physical-type parameters) (result-types result)))
        (error "native entry signature does not match scalar metadata")))

    ;; ---- Required foreign declarations ----

    (define (import-metadata node imports)
      (let* ((key (list (cadr node) (caddr node))) (declaration (assoc key imports)))
        (unless declaration (error "native import has no provider declaration" key))
        (vector (car key) (cadr key) (cadr declaration)
                (list->vector (map symbol->string (caddr declaration)))
                (if (null? (cadddr declaration)) "void" (symbol->string (car (cadddr declaration)))))))
    (define (write-metadata nodes description imports port)
      (let* ((metadata (append description
                               `((abi . "sfir-native-1")
                                 (imports . ,(list->vector
                                              (map (lambda (node) (import-metadata node imports))
                                                   (declarations nodes 'import)))))))
             (bytes (string->utf8 (json->string metadata))))
        (write-llvm (list "@sfir_native_metadata = constant [" (bytevector-length bytes)
                          " x i8] c" (llvm-quoted bytes) ", section \".sfir.entry\", align 1\n") port)))

    ;; ---- Fixed scalar bits bridge ----

    ;; Slots contain scalar bits, never heap references. The ordinary exported
    ;; function publishes its managed roots before a collecting call. This
    ;; bridge therefore needs no GC frame and holds no managed result.
    (define (llvm-type type)
      (case type ((i32 i64) (symbol->string type)) ((f32) "float") ((f64) "double")))
    (define (write-line port . pieces)
      (write-llvm pieces port) (newline port))
    (define (read-argument type index port)
      (let ((word (llvm-name "%word" index)) (narrow (llvm-name "%narrow" index))
            (value (llvm-name "%value" index)) (slot (llvm-name "%slot" index)))
        (write-line port "  " slot " = getelementptr i64, ptr %arguments, i64 " index)
        (write-line port "  " word " = load i64, ptr " slot ", align 8")
        (when (memq type '(i32 f32)) (write-line port "  " narrow " = trunc i64 " word " to i32"))
        (case type
          ((f32) (write-line port "  " value " = bitcast i32 " narrow " to float") value)
          ((f64) (write-line port "  " value " = bitcast i64 " word " to double") value)
          ((i32) narrow) ((i64) word))))
    (define (read-arguments parameters port)
      (let visit ((parameters parameters) (index 0) (arguments '()))
        (if (null? parameters) (reverse arguments)
            (let* ((type (physical-type (car parameters))) (value (read-argument type index port)))
              (visit (cdr parameters) (+ index 1) (cons (list (llvm-type type) " " value) arguments))))))
    (define (return-result result port)
      (case result
        ((Unit) (write-line port "  ret i64 0"))
        ((I64) (write-line port "  ret i64 %result"))
        ((F64) (write-line port "  %bits = bitcast double %result to i64\n  ret i64 %bits"))
        ((F32) (write-line port "  %bits = bitcast float %result to i32\n  %wide = zext i32 %bits to i64\n  ret i64 %wide"))
        (else (write-line port "  %wide = zext i32 %result to i64\n  ret i64 %wide"))))
    (define (write-bridge parameters result port)
      (write-line port "@sfir_native_arity = constant i64 " (length parameters))
      (write-line port "@" (llvm-quoted
                            (string-append "sfir_native_entry."
                                           (apply string-append (map (lambda (type) (string-append (symbol->string type) "_")) parameters))
                                           "." (symbol->string result)))
                  " = alias i64 (ptr), ptr @sfir_native_entry")
      (write-line port "define i64 @sfir_native_entry(ptr %arguments) {\nentry:")
      (let ((arguments (read-arguments parameters port)))
        (write-line port (if (eq? result 'Unit) "  call void" "  %result = call ")
                    (if (eq? result 'Unit) "" (llvm-type (physical-type result)))
                    " @\"wasm.entry\"(" (llvm-join arguments ", ") ")"))
      (return-result result port)
      (write-line port "}"))
    (define (write-native-entry module parameters result description imports port)
      (let ((nodes (resolve-wasm module)))
        (check-entry nodes parameters result)
        (write-metadata nodes description imports port)
        (write-bridge parameters result port)))))
