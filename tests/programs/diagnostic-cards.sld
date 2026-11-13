;; Console layout is pure and reusable; adapting errors preserves their
;; order and their ordinary text, including multiline messages.
(import
 (snail core base)
 (snail core io)
 (snail shell console)
 (snail shell diagnostic)
 (only (snail shell compiler read)
       Loc
       SourceDiagnostic
       Diagnostics
       diagnostics->string))

(define errors (→ Diagnostics)
  (Diagnostics (SourceDiagnostic (Loc "main.sld" 3 7) "expected I64, found String")
               (list (SourceDiagnostic (Loc "library.sld" 0 0) "first line\n\nlast line\n"))))

(define (main) (→ Unit) (! output-port)
  (write-line (repr (console-card "notice" "λ 😀\ttext")))
  (write-line (repr (console-card "" "")))
  (write-line (repr (console-card "two\nlines" "body")))
  (write-line (repr (diagnostics->console errors)))
  (write-line (repr (diagnostics->string errors))))
