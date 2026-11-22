(import
 (snail core base)
 (snail core io))

;; A large lazy computation uses ordinary runtime loops, not expanded graph code.
(define (total) (→ I64) (fold-left + 0 (iota 20000)))
(define (small) (→ (List I64)) (iota 170))
(define (copied) (→ (Array I64)) (array-copy (array-generate 511 (lambda (index) index))))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (write-line out (show (total)))
  (write-line out (show (length (small))))
  (write-line out (show (array-ref (copied) 510))))
