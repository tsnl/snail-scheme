;; The text style is independent of source diagnostics. JSON uses the same
;; error values, preserving control characters instead of decorating them.
(import
 (snail core base)
 (snail core io)
 (snail shell log)
 (snail shell diagnostic)
 (only (snail shell compiler read)
       Loc
       SourceDiagnostic
       Diagnostics))

(define errors (→ Diagnostics)
  (Diagnostics (SourceDiagnostic (Loc "main.sld" 3 7) "expected I64, found String")
               (list
                (SourceDiagnostic (Loc "library.sld" 0 0) "first\n\nlast \"quoted\"\t\r\x0;"))))

(define (color-codes (level Level)) (→ Unit) (! output-port)
  (write (map char->integer (string->list (log->string level "" #t))))
  (newline))

(define (main) (→ Unit) (! output-port)
  (write-line (repr (log->string (Error) "first\n\nlast\n" #f)))
  (write-line (log->string (Warning) "warning" #f))
  (write-line (log->string (Info) "information" #f))
  (write-line (log->string (Note) "context" #f))
  (write-line (repr (log->string (Info) "λ 😀\t\r\x0;" #f)))
  (for-each color-codes (list (Error) (Warning) (Info) (Note)))
  (write-line (repr (diagnostics->output (TextErrors) errors #f)))
  (write-line (diagnostics->output (JsonErrors) errors #t))
  (write-line (message->output (JsonErrors) "line\n\"quoted\"\\\x1b;" #t)))
