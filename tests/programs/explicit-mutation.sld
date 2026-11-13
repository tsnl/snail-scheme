(import
 (snail core base)
 (snail core io))

(record Total
  ((value I64)))

;; Pure code threads its accumulation directly.
(define (sum (items (List I64))) (→ I64)
  (fold-left + 0 items))

;; Other effects still need declaring.
(define (noisy-sum (items (List I64))) (→ I64) (! mut output-port)
  (let ((total (new Total (value 0))))
    (for-each
     (lambda (item) (write-line (show item)) (set! (● total value) (+ (● total value) item)))
     items)
    (● total value)))

;; Passing an object around without mutating it needs no check.
(define (first-total (totals (List Total))) (→ (Option Total))
  (match totals
    ((Cons cell _) (Some cell))
    ((Nil) (None))))

(define (main) (→ Unit) (! mut output-port)

  (display (sum (list 1 2 3 4)))
  (newline)
  (display (noisy-sum (list 5 6)))
  (newline)
  (display
   (match (first-total (list (new Total (value 7)))) ((Some cell) (● cell value)) ((None) 0)))
  (newline)
  (unit))
