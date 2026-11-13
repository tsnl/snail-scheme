(import
 (snail core base))

;; Entry points return checksums; the host times repeated calls after warm-up.
;; Each compared revision supplies its own source spelling.
(record Point
  ((x I64)
   (y I64)))

(record Particle
  ((position Point)
   (velocity Point)))

(define (scalar (count I64)) (→ I64)
  (let loop ((left count) (value 0))
    (if (= left 0) value
        (loop (- left 1) (+ value (modulo left 97))))))

(define (advance (value Particle)) (→ Particle)
  (new Particle (position (new Point (x (+ (● value position x) (● value velocity x)))
                               (y (+ (● value position y) (● value velocity y)))))
       (velocity (● value velocity))))

(define (records (count I64)) (→ I64)
  (let loop ((left count)
             (value
              (new Particle (position (new Point (x 0) (y 0))) (velocity (new Point (x 1) (y 2))))))
    (if (= left 0) (+ (● value position x) (● value position y))
        (loop (- left 1) (advance value)))))

(define (record-list (count I64)) (→ I64)
  (let build ((left count) (items (Nil)))
    (if (= left 0)
        (fold-left (lambda (total point) (+ total (+ (● point x) (● point y)))) 0 items)
        (build (- left 1) (Cons (new Point (x left) (y left)) items)))))

(define (vectors (count I64)) (→ I64) (! mut)
  (let ((values (make-vector count 0)))
    (let fill ((index 0))
      (when (< index count)
        (vector-set! values index index)
        (fill (+ index 1))))
    (let sum ((index 0) (total 0))
      (if (= index count) total
          (sum (+ index 1) (+ total (vector-ref values index)))))))

(expose scalar "scalar")
(expose records "records")
(expose record-list "record_list")
(expose vectors "vectors")

(define (main) (→ Unit) (unit))
