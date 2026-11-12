(import
 (snail core base)
 (snail core io))

;; The counter is allocated inside and never leaves, so `sum` may be total.
(define (sum (items (List I64))) (→ I64)
  (let ((total (ref 0)))
    (for-each (lambda (item) (ref-set! total (+ (ref-get total) item))) items)
    (ref-get total)))

;; Other effects still need declaring.
(define (noisy-sum (items (List I64))) (→ I64) (! output-port)
  (let ((total (ref 0)))
    (for-each (lambda (item) (write-line (show item)) (ref-set! total (+ (ref-get total) item)))
              items)
    (ref-get total)))

;; Passing a cell around without mutating it needs no check.
(define (first-cell (cells (List (Ref I64)))) (→ (Option (Ref I64)))
  (match cells
    ((Cons cell _) (Some cell))
    ((Nil) (None))))

(define main
  (lambda ()
    (display (sum (list 1 2 3 4)))
    (newline)
    (display (noisy-sum (list 5 6)))
    (newline)
    (display (match (first-cell (list (ref 7))) ((Some cell) (ref-get cell)) ((None) 0)))
    (newline)
    (unit)))
