;; Lofi compilation produces optimized Wasm with an explicit scalar entry.
;; Provider linkage is separate from compiler artifact construction.
(define-library (lofi compiler artifact)
  (export make-entry entry? entry-library entry-export
          artifact? artifact-entry artifact-parameters artifact-result artifact-bytes
          emit-artifact entry-description)
  (import
   (scheme base)
   (scheme file)
   (scheme write)
   (only (chibi temp-file) call-with-temp-dir)
   (only (lofi host json) json->string)
   (lofi host build-host)
   (lofi host chromium-trace)
   (lofi host wasm-optimize)
   (only (lofi host wasm) write-wasm))
  (begin

    ;; ---- Public entry identity ----

    (define-record-type <entry>
      (new-entry library export) entry?
      (library entry-library)
      (export entry-export))
    (define (make-entry library export)
      (unless (and (list? library) (pair? library) (symbol? export))
        (error "entry requires a nonempty library key and an export name"))
      (for-each (lambda (name) (unless (symbol? name) (error "entry library key requires names" name))) library)
      (new-entry (append library '()) export))

    ;; ---- Artifact values ----

    ;; The ABI always exports `entry` after one-shot `main` initialization.
    ;; Semantic scalar types accompany the bytes for a later typed adapter.
    (define-record-type <artifact>
      (make-artifact entry parameters result bytes) artifact?
      (entry artifact-entry)
      (parameters artifact-parameters)
      (result artifact-result)
      (bytes artifact-bytes))
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
    ;; transport for Lofi syntax, bindings, or live compiler objects.
    (define (write-unsigned-leb value port)
      (let ((rest (quotient value 128)) (low (remainder value 128)))
        (write-u8 (if (zero? rest) low (+ low 128)) port)
        (unless (zero? rest) (write-unsigned-leb rest port))))
    (define (entry-description entry parameters result)
      (unless (and (let visit ((types parameters))
                     (or (null? types) (and (memq (car types) '(I32 I64 F32 F64 Bool Char)) (visit (cdr types)))))
                   (memq result '(I32 I64 F32 F64 Bool Char Unit)))
        (error "execution artifact requires scalar entry parameters and a scalar or Unit result"))
      `((version . 1) (library . ,(list->vector (map symbol->string (entry-library entry))))
        (export . ,(symbol->string (entry-export entry)))
        (parameters . ,(list->vector (map symbol->string parameters)))
        (result . ,(symbol->string result))))
    (define (entry-metadata entry parameters result)
      (string->utf8 (json->string (entry-description entry parameters result))))
    (define (wasm-entry-section entry parameters result)
      (let* ((name (string->utf8 "lofi.entry")) (data (entry-metadata entry parameters result))
             (payload (open-output-bytevector)) (section (open-output-bytevector)))
        (write-unsigned-leb (bytevector-length name) payload)
        (write-bytevector name payload) (write-bytevector data payload)
        (let ((bytes (get-output-bytevector payload)))
          (write-u8 0 section) (write-unsigned-leb (bytevector-length bytes) section)
          (write-bytevector bytes section) (get-output-bytevector section))))

    ;; ---- Mandatory Wasm optimization ----

    (define (wasm-artifact module directory)
      (let ((text (string-append directory "/source.wat"))
            (binary (string-append directory "/source.wasm")) (output (string-append directory "/artifact.wasm")))
        (check-binaryen-tools)
        (call-with-output-file text (lambda (port) (write-wasm module port)))
        (assemble-wasm text binary)
        (optimize-wasm binary output)
        (file-bytes output)))
    (define (emit-artifact module entry parameters result)
      (call-with-temp-dir
       "lofi-artifact"
       (lambda (directory preserve)
         (with-chromium-trace-to
          (string-append directory "/compile.trace.json")
          (lambda ()
            (make-artifact entry parameters result
                           (bytevector-append (wasm-artifact module directory)
                                              (wasm-entry-section entry parameters result)))))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-artifact)
    (import
     (lofi host test-utils))
    (begin
      (define (test-wasm-section-lengths)
        (let ((port (open-output-bytevector)))
          (for-each (lambda (value) (write-unsigned-leb value port)) '(0 127 128 624485))
          (expect (get-output-bytevector port) #u8(0 127 128 1 229 142 38))))
      (define (test-artifact)
        (run-test test-wasm-section-lengths))))
   (else)))
