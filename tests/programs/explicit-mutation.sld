(import
 (snail core base)
 (snail core io))

(record Total
  ((value I64)))

;; Pure code threads its accumulation directly.
(define (sum (items (List I64))) (→ I64)
  (fold-left + 0 items))

;; Other effects still need declaring.
(define (noisy-sum (out OutputPort) (items (List I64))) (→ I64) (! mut)
  (let ((total (new Total (value 0))))
    (for-each
     (lambda (item) (write-line out (show item)) (set! (● total value) (+ (● total value) item)))
     items)
    (● total value)))

;; Passing an object around without mutating it needs no check.
(define (first-total (totals (List Total))) (→ (Option Total))
  (match totals
    ((Cons cell _) (Some cell))
    ((Nil) (None))))

(define (main (out OutputPort)) (→ Unit) (! mut)

  (display out (sum (list 1 2 3 4)))
  (newline out)
  (display out (noisy-sum out (list 5 6)))
  (newline out)
  (display out
   (match (first-total (list (new Total (value 7)))) ((Some cell) (● cell value)) ((None) 0)))
  (newline out)
  (unit))
