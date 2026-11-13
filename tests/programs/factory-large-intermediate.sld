(import
 (snail core base)
 (snail core io))

;; A large lazy computation uses ordinary runtime loops, not expanded graph code.
(define (total) (→ I64) (fold-left + 0 (iota 20000)))
(define (small) (→ (List I64)) (iota 170))
(define (array) (→ (Vector I64)) (vector-copy (vector-generate 511 (lambda (index) index))))

(define (main) (→ Unit) (! output-port)
  (write-line (show (total)))
  (write-line (show (length (small))))
  (write-line (show (vector-ref (array) 510))))
