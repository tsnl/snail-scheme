;; Target adapters consume emitted Wasm and return owned artifact bytes. Both
;; routes pass through Binaryen; provider linking and execution stay outside.
(define-library (snail-sfir artifact)
  (export make-entry entry? entry-library entry-export
          target? target-name wasm-target native64-target
          make-native-import native-import?
          artifact? artifact-target artifact-entry artifact-parameters artifact-result artifact-bytes
          emit-artifact)
  (import (scheme base) (scheme file)
          (only (chibi temp-file) call-with-temp-dir)
          (only (chibi json) json->string)
          (snail-scheme build-host) (snail-scheme chromium-trace)
          (snail-scheme wasm-optimize) (snail-scheme native)
          (only (snail-scheme llvm) current-native-imports)
          (only (snail-scheme wasm) write-wasm))
  (begin

    ;; ---- Entry and target descriptions ----

    (define-record-type <entry>
      (new-entry library export) entry?
      (library entry-library) (export entry-export))
    (define (make-entry library export)
      (unless (and (list? library) (pair? library) (symbol? export))
        (error "entry requires a nonempty library key and an export name"))
      (for-each (lambda (name) (unless (symbol? name) (error "entry library key requires names" name))) library)
      (new-entry (append library '()) export))

    ;; Native declarations use physical Wasm scalar types. They describe the
    ;; target's C symbols and signatures; they neither find nor link providers.
    (define-record-type <native-import>
      (new-native-import key symbol parameters results) native-import?
      (key native-import-key) (symbol native-import-symbol)
      (parameters native-import-parameters) (results native-import-results))
    (define (physical-scalars? types)
      (and (list? types)
           (let visit ((types types))
             (or (null? types) (and (memq (car types) '(i32 i64 f32 f64)) (visit (cdr types)))))))
    (define (make-native-import module name symbol parameters result)
      (unless (and (string? module) (string? name) (string? symbol)
                   (physical-scalars? parameters) (or (eq? result 'void) (physical-scalars? (list result))))
        (error "native import requires strings, scalar parameters and a scalar or void result"))
      (new-native-import (list module name) symbol (append parameters '())
                         (if (eq? result 'void) '() (list result))))
    (define-record-type <target>
      (make-target name imports) target?
      (name target-name) (imports target-imports))
    (define wasm-target (make-target 'wasm '()))
    (define (native64-target imports)
      (unless (list? imports) (error "native64 target requires a list of native imports"))
      (let visit ((imports imports) (keys '()) (declarations '()))
        (if (null? imports) (make-target 'native64 (reverse declarations))
            (let ((entry (car imports)))
              (unless (native-import? entry) (error "native64 target requires native import values" entry))
              (when (member (native-import-key entry) keys) (error "duplicate native import" (native-import-key entry)))
              (visit (cdr imports) (cons (native-import-key entry) keys)
                     (cons (list (native-import-key entry) (native-import-symbol entry)
                                 (native-import-parameters entry) (native-import-results entry)) declarations))))))

    ;; ---- Artifact values ----

    ;; The ABI always exports `entry` after one-shot `main` initialization.
    ;; Semantic scalar types accompany the bytes for a later typed adapter.
    ;; Native bytes are an unlinked x86-64 Linux relocatable object, not an instance.
    (define-record-type <artifact>
      (make-artifact target entry parameters result bytes) artifact?
      (target artifact-target) (entry artifact-entry)
      (parameters artifact-parameters) (result artifact-result) (bytes artifact-bytes))
    (define (file-bytes path)
      (call-with-port (open-binary-input-file path)
        (lambda (input)
          (let ((output (open-output-bytevector)))
            (let read-chunks ((bytes (read-bytevector 65536 input)))
              (unless (eof-object? bytes)
                (write-bytevector bytes output) (read-chunks (read-bytevector 65536 input))))
            (get-output-bytevector output)))))

    ;; ---- Portable Wasm entry metadata ----

    ;; A custom section retains the semantic types after target optimization.
    ;; The execution adapter checks their physical signature against the actual
    ;; Wasm exports before initialization. This is artifact metadata, not a
    ;; transport for SFIR syntax, bindings, or live compiler objects.
    (define (write-unsigned-leb value port)
      (let ((rest (quotient value 128)) (low (remainder value 128)))
        (write-u8 (if (zero? rest) low (+ low 128)) port)
        (unless (zero? rest) (write-unsigned-leb rest port))))
    (define (entry-metadata entry parameters result)
      (string->utf8
       (json->string `((version . 1) (library . ,(list->vector (map symbol->string (entry-library entry))))
                       (export . ,(symbol->string (entry-export entry)))
                       (parameters . ,(list->vector (map symbol->string parameters)))
                       (result . ,(symbol->string result))))))
    (define (wasm-entry-section entry parameters result)
      (let* ((name (string->utf8 "sfir.entry")) (data (entry-metadata entry parameters result))
             (payload (open-output-bytevector)) (section (open-output-bytevector)))
        (write-unsigned-leb (bytevector-length name) payload)
        (write-bytevector name payload) (write-bytevector data payload)
        (let ((bytes (get-output-bytevector payload)))
          (write-u8 0 section) (write-unsigned-leb (bytevector-length bytes) section)
          (write-bytevector bytes section) (get-output-bytevector section))))

    ;; ---- Existing target tool routes ----

    (define (wasm-artifact module directory)
      (let ((text (string-append directory "/source.wat"))
            (binary (string-append directory "/source.wasm")) (output (string-append directory "/artifact.wasm")))
        (check-binaryen-tools)
        (call-with-output-file text (lambda (port) (write-wasm module port)))
        (assemble-wasm text binary)
        (optimize-scheme-wasm binary output)
        (file-bytes output)))
    (define (native-artifact module target directory)
      (let ((llvm (string-append directory "/module.ll")) (output (string-append directory "/artifact.o")))
        (parameterize ((current-native-imports (target-imports target)))
          (native-wasm->llvm module directory llvm))
        (run-command "native.object"
                     (list (tool-name "CLANG" "clang") "--target=x86_64-unknown-linux-gnu" "-O3"
                           "-ffunction-sections" "-fdata-sections" "-c" llvm "-o" output))
        (file-bytes output)))
    (define (emit-artifact module entry parameters result target)
      (unless (target? target) (error "compile requires a target value" target))
      (call-with-temp-dir
       "sfir-artifact"
       (lambda (directory preserve)
         (with-chromium-trace-to
          (string-append directory "/compile.trace.json")
          (lambda ()
            (make-artifact target entry parameters result
                           (case (target-name target)
                             ((wasm) (bytevector-append (wasm-artifact module directory)
                                                        (wasm-entry-section entry parameters result)))
                             ((native64) (native-artifact module target directory))))))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-artifact)
    (import (snail-scheme test-utils))
    (begin
      (define (test-target-descriptions)
        (let* ((import (make-native-import "demo" "read" "demo_read" '(i32) 'i64))
               (target (native64-target (list import))))
          (expect (target-name wasm-target) 'wasm)
          (expect (target-name target) 'native64)
          (expect (target-imports target) '((("demo" "read") "demo_read" (i32) (i64))))
          (expect (guard (failure (else (error-object-message failure))) (native64-target (list import import)))
                  "duplicate native import")
          (expect (guard (failure (else #t)) (make-native-import "demo" "read" "demo_read" '(eqref) 'i64) #f) #t)
          (expect (guard (failure (else #t)) (native64-target '((("demo" "read") "demo_read" (i32) (i64)))) #f) #t)))
      (define (test-wasm-section-lengths)
        (let ((port (open-output-bytevector)))
          (for-each (lambda (value) (write-unsigned-leb value port)) '(0 127 128 624485))
          (expect (get-output-bytevector port) #u8(0 127 128 1 229 142 38))))
      (define (test-artifact)
        (run-test test-target-descriptions)
        (run-test test-wasm-section-lengths))))
   (else)))
