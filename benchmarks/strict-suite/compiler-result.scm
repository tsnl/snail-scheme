;; The upstream compiler captures a continuation only to abort its current
;; compilation with #f. This adapter makes that effect visible in result types.
;; Every intervening call must match failure before performing its next effect;
;; the complete adapted kernel, including these checks, also runs under Chez.

;; ---- Compiler aborts stop at the nearest installed handler ----

(define-data (CompilerResult T)
  (compiler-success (value T compiler-success-value))
  (compiler-failure))
(define compiler-handler-active (ref #f))

;; The source never exposes, stores elsewhere, or resumes the captured handler.
;; Its only argument is #f. The active bit therefore preserves exactly the
;; information abort needs; nested calls restore the prior scope on either result.
(: compiler-with-exception-handling (-> (-> (CompilerResult Bool)) Bool))
(define (compiler-with-exception-handling procedure)
  (let ((previous (ref-get compiler-handler-active)))
    (ref-set! compiler-handler-active #t)
    (let ((result (procedure)))
      (ref-set! compiler-handler-active previous)
      (match result
        ((compiler-success value) value)
        ((compiler-failure) #f)))))

(: compiler-abort-result (All (T) (-> (CompilerResult T))))
(define (compiler-abort-result)
  (if (ref-get compiler-handler-active) (compiler-failure)
      (datum-fail "Internal error, no exception handler at this point")))

;; Ordinary primitive failures are deliberately outside this protocol. Just as
;; in the source, a host failure during procedure escapes before restoration;
;; this is not a general exception facility or a dynamic-wind implementation.
