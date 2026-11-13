(import
 (snail core base))

(define total (→ I64) (fold-left + 0 (iota 64)))
(define items (→ (Vector I64)) (vector-generate 64 (lambda (index) index)))

(define (scalar-read (count I64)) (→ I64)
  (let loop ((left count) (sum 0))
    (if (= left 0) sum (loop (- left 1) (+ sum total)))))

(define (aggregate-read (count I64)) (→ I64)
  (let loop ((left count) (sum 0))
    (if (= left 0) sum (loop (- left 1) (+ sum (vector-ref items 63))))))

(expose scalar-read "scalar-read")
(expose aggregate-read "aggregate-read")
(define (main) (→ Unit) (unit))
