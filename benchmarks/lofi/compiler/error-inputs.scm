;; Malformed programs must abort, then the canonical program must still compile.
((if) m68000)
((lambda (x x) x) m68000)
((set! 5 6) m68000)
((quote a b) m68000)
(17 missing-target)
