(import
 (lofi core)
 (macro literal-decisions))

;; The first rule matches marker, then fails on its numeric literal. Adding
;; marker must still preserve the observed comparison from that failed rule.
(check-then-bind marker 42)
marker
