(import
 (snail core base))

;; Each measurement creates a wrapper locally and includes its allocation,
;; cold misses, steady hits and final release in the measured interval.
(define (expensive (key I64)) (→ I64)
  (let loop ((left 64) (value (+ key 1)))
    (if (= left 0) value
        (loop (- left 1) (modulo (+ (* value 17) left) 1000003)))))

(define (cheap (key I64)) (→ I64) (* key 3))

(define (run (f (Fn I64 → I64)) (count I64) (keys I64)) (→ I64)
  (let loop ((index 0) (total 0))
    (if (= index count) total
        (loop (+ index 1) (+ total (f (modulo index keys)))))))

(define (plain-expensive (count I64)) (→ I64) (run expensive count 128))
(define (cached-expensive (count I64)) (→ I64) (run (cache expensive) count 128))
(define (lru-expensive (count I64)) (→ I64) (run (lru-cache 128 expensive) count 128))
(define (plain-cheap (count I64)) (→ I64) (run cheap count 128))
(define (cached-cheap (count I64)) (→ I64) (run (cache cheap) count 128))
(define (plain-misses (count I64)) (→ I64) (run cheap count count))
(define (cached-misses (count I64)) (→ I64) (run (cache cheap) count count))

(expose plain-expensive "plain_expensive")
(expose cached-expensive "cached_expensive")
(expose lru-expensive "lru_expensive")
(expose plain-cheap "plain_cheap")
(expose cached-cheap "cached_cheap")
(expose plain-misses "plain_misses")
(expose cached-misses "cached_misses")

(define (main) (→ Unit) (unit))
