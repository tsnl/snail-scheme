;; Terminal presentation is a caller of the compiler's structured errors.
;; Plain diagnostic strings and editor reports keep their own contracts.
(define-library (snail shell diagnostic)
  (export
   diagnostics->console)
  (import
   (snail core base)
   (snail shell console)
   (only (snail shell compiler read)
         Diagnostics
         SourceDiagnostic
         diagnostics->list
         diagnostic->string))
  (begin

    ;; ---- Source errors ----

    (define (diagnostics->console (diagnostics Diagnostics)) (→ String)
      (string-join (map diagnostic-card (diagnostics->list diagnostics)) "\n\n"))

    (define (diagnostic-card (diagnostic SourceDiagnostic)) (→ String)
      (console-card "error" (diagnostic->string diagnostic)))

    ))
