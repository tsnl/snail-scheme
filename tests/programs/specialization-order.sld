(import
 (snail core base)
 (snail core io)
 (sample specialization))

;; Definitions initialize before statements, in both whole-program and
;; library builds, even when a statement precedes the definition in source.
(write-line (show (advance)))

(: third I64)
(define third (+ second (advance)))

(write-line (show first))
(write-line (show second))
(write-line (show third))
(write-line (show (round-trip 17 100)))
(write-line (round-trip "again" 99))
(write-line (show (round-trip 23 2)))

;; The library module imports this same function for both its host wrapper
;; and its ordinary call; neither path may enqueue an imported body.
(expose fixed "fixed")
(write-line (show (fixed 41)))
