;; WebAssembly text to a binary module, in-process, for tools written in
;; Snail-Core: the toolchain's runtime assembles it with the `wat` crate.
;; A program linked with the plain runtime cannot use it, since
;; that runtime leaves the parser out; stage 0 links a tool with the
;; toolchain's runtime (`build-toolchain-tool`).
(define-library (snail shell assembler)
  (export
   assemble)
  (import
   (snail core base)
   (snail shell utf8))
  (begin

    ;; ---- Assembling ----

    ;; The text is staged as any final String is. The result stays in the
    ;; runtime until the next assembly: the module, or the parser's message
    ;; as UTF-8, which these read a byte at a time.
    (extern assemble-staged "snail.core.support" "snail:assembler/assemble" (-> String I32))
    (extern output-length "snail.core.support" "snail:assembler/output-length" (-> I32))
    (extern output-byte "snail.core.support" "snail:assembler/output-byte" (-> I32 I32))

    ;; The binary module `text` describes, or the parser's message, which
    ;; names the line and column of the problem.
    (: assemble (-> String (Result Bytes String)))
    (define (assemble text)
      (let* ((status (assemble-staged text))
             (output (vector-generate (i32->i64 (output-length))
                                      (lambda (index) (i32->u8 (output-byte (i64->i32 index)))))))
        (if (= status 0)
            (Ok output)
            (Err (match (utf8->string output)
                   ((Ok message) message)
                   ((Err _) "the assembler's message is not UTF-8"))))))

    ))
