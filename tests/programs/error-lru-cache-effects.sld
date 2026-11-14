(import
 (snail core base)
 (snail core io))

;; Zero capacity obeys the same static contract, even though it bypasses storage.
(define (main) (→ Unit) (! output-port)
  (let ((memo (lru-cache 0 write-line))) (memo "effect")))
