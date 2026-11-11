;; WebAssembly assembly and static linking, in-process, for compiler tools.
;; The toolchain runtime uses `wat` and `wasm-fuse`.
;; A program linked with the plain runtime cannot use it, since
;; that runtime leaves the parser out; stage 0 links a tool with the
;; toolchain's runtime (`build-toolchain-tool`).
(define-library (snail shell assembler)
  (export
   assemble
   link)
  (import
   (snail core base)
   (snail shell utf8))
  (begin

    ;; ---- Assembly and linking ----

    ;; Requests use the compiler's String/Bytes staging. The result stays in
    ;; the runtime until the next request: the module, or the error message
    ;; as UTF-8, which these read a byte at a time.
    (extern assemble-staged
            "snail.core.support"
            "snail:assembler/assemble"
            (impl (Fn String → I32)))
    (extern link-staged "snail.core.support" "snail:assembler/link" (impl (Fn I32 Bytes → I32)))
    (extern output-length "snail.core.support" "snail:assembler/output-length" (impl (Fn → I32)))
    (extern output-byte "snail.core.support" "snail:assembler/output-byte" (impl (Fn I32 → I32)))

    ;; The binary module `text` describes, or the parser's message, which
    ;; names the line and column of the problem.

    (define (assemble (text String)) (→ (Result Bytes String))
      (result (assemble-staged text)))

    ;; One complete request: the runtime followed by the program's UTF-8 text.
    ;; Neither operation depends on a previous request's input or output.

    (define (link (text String) (runtime Bytes)) (→ (Result Bytes String))
      (result (link-staged (i64->i32 (vector-length runtime))
                           (vector-append runtime (string->utf8 text)))))

    (define (result (status I32)) (→ (Result Bytes String))
      (let ((output (vector-generate (i32->i64 (output-length))
                                     (lambda (index) (i32->u8 (output-byte (i64->i32 index)))))))
        (if (= status 0)
            (Ok output)
            (Err (match (utf8->string output)
                   ((Ok message) message)
                   ((Err _) "the assembler's message is not UTF-8"))))))

    ))
