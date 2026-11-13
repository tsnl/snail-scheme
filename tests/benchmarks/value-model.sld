(import
 (snail core base))

;; Entry points return checksums; the host times repeated calls after warm-up.
;; The migration driver translates vector spellings for the old compiler.
(struct Point
  ((x I64)
   (y I64)))

(struct Particle
  ((position Point)
   (velocity Point)))

(define (scalar (count I64)) (→ I64)
  (let loop ((left count) (value 0))
    (if (= left 0) value
        (loop (- left 1) (+ value (modulo left 97))))))

(define (advance (value Particle)) (→ Particle)
  (Particle (Point (+ (● value position x) (● value velocity x))
                   (+ (● value position y) (● value velocity y)))
            (● value velocity)))

(define (records (count I64)) (→ I64)
  (let loop ((left count) (value (Particle (Point 0 0) (Point 1 2))))
    (if (= left 0) (+ (● value position x) (● value position y))
        (loop (- left 1) (advance value)))))

(define (record-list (count I64)) (→ I64)
  (let build ((left count) (items (Nil)))
    (if (= left 0)
        (fold-left (lambda (total point) (+ total (+ (● point x) (● point y)))) 0 items)
        (build (- left 1) (Cons (Point left left) items)))))

(define (vectors (count I64)) (→ I64) (! mut)
  (let ((values (make-vector count 0)))
    (let fill ((index 0))
      (when (< index count)
        (vector-set! values index index)
        (fill (+ index 1))))
    (let sum ((index 0) (total 0))
      (if (= index count) total
          (sum (+ index 1) (+ total (vector-ref values index)))))))

(define (grow (count I64)) (→ I64) (! mut)
  (let ((values (vector)))
    (let fill ((index 0))
      (when (< index count)
        (vector-push! values index)
        (fill (+ index 1))))
    (let sum ((index 0) (total 0))
      (if (= index (vector-length values)) total
          (sum (+ index 1) (+ total (vector-ref values index)))))))

(expose scalar "scalar")
(expose records "records")
(expose record-list "record_list")
(expose vectors "vectors")
(expose grow "grow")

(define (main) (→ Unit) (unit))
