;; Two application kernels with caller-owned working sets. Setup, host
;; inspection and heap counters are separate from the timed exports.
(import
 (snail core base)
 (snail shell game physics)
 (apps siegework grid)
 (apps siegework terrain))

;; ---- Last Mile walls ----

(record WallId
  ((slot I64)))

(record Walls
  ((bounds (Array F64))
   (ids (Array WallId))
   (slots (Array I64))))

(define (prepare-shared (count I64) (phase I64)) (→ (List Footprint))
  (map (lambda (i)
         (footprint (+ 2.0 (i64->f64 (remainder i 31)))
                    (- (i64->f64 (remainder (+ (* i 7) phase) 11)) 5.0) 0.5 1.25)) (iota count)))

(define (cast-shared (walls (List Footprint)) (count I64) (seed F64)) (→ F64)
  (let ((p (xz 0.0 seed)) (flat (xz 1.0 0.0)) (slope (xz 1.0 0.125)))
    (let loop ((n count) (z seed) (sum 0.0))
      (if (= n 0) sum
          (begin
            (set! (● p z) z)
            (let ((hit (trace-distance p (if (= (remainder n 2) 0) flat slope) 40.0 walls)))
              (loop (- n 1) (if (> z 5.0) (- z 9.875) (+ z 0.28125)) (+ sum hit))))))))

(define (shuffled-slots (count I64) (phase I64)) (→ (Array I64))
  (let ((slots (array-generate count (lambda (i) i))))
    (let shuffle ((i (- count 1)) (state (+ phase 1)))
      (when (> i 0)
        (let* ((state (remainder (* state 48271) 2147483647)) (j (remainder state (+ i 1)))
               (saved (array-ref slots i)))
          (array-set! slots i (array-ref slots j))
          (array-set! slots j saved)
          (shuffle (- i 1) state))))
    slots))

(define (prepare-walls (count I64) (phase I64)) (→ Walls)
  (let* ((bounds (make-array (* count 4) 0.0))
         (slots (shuffled-slots count phase))
         (ids (array-map (lambda (i) (new WallId (slot i))) slots)))
    (let fill ((i 0))
      (when (< i count)
        (let ((at (* i 4)) (x (+ 2.0 (i64->f64 (remainder i 31))))
              (z (- (i64->f64 (remainder (+ (* i 7) phase) 11)) 5.0)))
          (array-set! bounds at (- x 0.25))
          (array-set! bounds (+ at 1) (+ x 0.25))
          (array-set! bounds (+ at 2) (- z 0.625))
          (array-set! bounds (+ at 3) (+ z 0.625))
          (fill (+ i 1)))))
    (new Walls (bounds bounds) (ids ids) (slots slots))))

;; In this workload x starts at zero with unit velocity. The z direction
;; is either parallel or positive. Keep the two slab limits in registers.
(define (intersect (bounds (Array F64)) (at I64) (z F64) (dz F64) (reach F64)) (→ F64)
  (let ((near (max 0.0 (array-ref bounds at))) (far (min reach (array-ref bounds (+ at 1))))
        (north (array-ref bounds (+ at 2))) (south (array-ref bounds (+ at 3))))
    (if (= dz 0.0)
        (if (and (>= z north) (<= z south) (<= near far)) near reach)
        (let ((entry (max near (/ (- north z) dz))) (exit (min far (/ (- south z) dz))))
          (if (<= entry exit) entry reach)))))

;; Probe a four-coordinate window, including incomplete windows in the
;; bounds tests. The timed paths always visit whole walls.
(define (probe-wall (walls Walls) (at I64)) (→ F64)
  (intersect (● walls bounds) at -5.0 0.0 40.0))

(define (trace-dense (bounds (Array F64)) (z F64) (dz F64) (at I64) (reach F64)) (→ F64)
  (if (= at (array-length bounds)) reach
      (trace-dense bounds z dz (+ at 4) (intersect bounds at z dz reach))))

(define (trace-ids (bounds (Array F64)) (ids (Array WallId)) (z F64) (dz F64) (i I64) (reach F64))
  (→ F64)
  (if (= i (array-length ids)) reach
      (let ((at (* 4 (● (array-ref ids i) slot))))
        (trace-ids bounds ids z dz (+ i 1) (intersect bounds at z dz reach)))))

(define (trace-slots (bounds (Array F64)) (slots (Array I64)) (z F64) (dz F64) (i I64) (reach F64))
  (→ F64)
  (if (= i (array-length slots)) reach
      (let ((at (* 4 (array-ref slots i))))
        (trace-slots bounds slots z dz (+ i 1) (intersect bounds at z dz reach)))))

(define (cast-batch (walls Walls) (n I64) (z F64) (mode I32) (sum F64)) (→ F64)
  (if (= n 0) sum
      (let* ((dz (if (= (remainder n 2) 0) 0.0 0.125))
             (hit (cond ((= mode 0) (trace-dense (● walls bounds) z dz 0 40.0))
                        ((= mode 1) (trace-ids (● walls bounds) (● walls ids) z dz 0 40.0))
                        (else (trace-slots (● walls bounds) (● walls slots) z dz 0 40.0)))))
        (cast-batch walls (- n 1) (if (> z 5.0) (- z 9.875) (+ z 0.28125)) mode (+ sum hit)))))

(define (cast (walls Walls) (count I64) (seed F64) (mode I32)) (→ F64)
  (cast-batch walls count seed mode 0.0))

;; ---- Siegework distance fields ----

(record GridWork
  ((open (Array Bool))
   (distance (Array I64))
   (queue (Array I64))
   (hub I64)))

(define (prepare-grid (seed I64)) (→ GridWork)
  (let* ((land (new-land seed))
         (open (array-map (lambda (g) (match g ((Open) #t) ((Ice) #t) (_ #f))) (● land ground)))
         (size (array-length open)))
    (new GridWork (open open) (distance (make-array size -1)) (queue (make-array size 0))
         (hub (cell-index (● land hub))))))

(define (grid-open? (grid GridWork) (slot I64)) (→ Bool) (array-ref (● grid open) slot))
(define (grid-hub (grid GridWork)) (→ I64) (● grid hub))
(define (grid-distance (grid GridWork) (slot I64)) (→ I64) (array-ref (● grid distance) slot))

(define (shipping-field! (grid GridWork) (goal I64)) (→ Unit)
  (set! (● grid distance) (distance-field (● grid open) (list (index-cell goal)))))

;; Each reached cell enters the queue once. Slots are stable for the
;; map's lifetime, and the same storage serves the next path query.
(define (enqueue (grid GridWork) (slot I64) (steps I64) (end I64)) (→ I64)
  (if (and (array-ref (● grid open) slot) (= (grid-distance grid slot) -1))
      (begin (array-set! (● grid distance) slot steps)
             (array-set! (● grid queue) end slot)
             (+ end 1))
      end))

(define (expand-cell (grid GridWork) (slot I64) (end I64)) (→ I64)
  (let* ((steps (+ 1 (grid-distance grid slot))) (x (remainder slot map-size))
         (end (if (< (+ x 1) map-size) (enqueue grid (+ slot 1) steps end) end))
         (end (if (> x 0) (enqueue grid (- slot 1) steps end) end))
         (end (if (< (+ slot map-size) (* map-size map-size))
                  (enqueue grid (+ slot map-size) steps end) end)))
    (if (>= slot map-size) (enqueue grid (- slot map-size) steps end) end)))

(define (clear-distance! (distance (Array I64)) (i I64)) (→ Unit)
  (when (< i (array-length distance))
    (array-set! distance i -1)
    (clear-distance! distance (+ i 1))))

(define (visit! (grid GridWork) (next I64) (end I64)) (→ Unit)
  (when (< next end)
    (visit! grid (+ next 1) (expand-cell grid (array-ref (● grid queue) next) end))))

(define (packed-field! (grid GridWork) (goal I64)) (→ Unit)
  (clear-distance! (● grid distance) 0)
  (array-set! (● grid distance) goal 0)
  (array-set! (● grid queue) 0 goal)
  (visit! grid 0 1))

(extern profile! "snail.core.support" "snail:gc/profile" (Fn I32 → Unit))
(extern allocations "snail.core.support" "snail:gc/profile-allocations" (Fn → I64))
(extern collections "snail.core.support" "snail:gc/collections" (Fn → I32))
(define (enable-profile! (enabled I32)) (→ Unit) (profile! enabled))
(define (allocation-count) (→ I64) (allocations))
(define (collection-count) (→ I32) (collections))

(expose prepare-walls "prepare-walls")
(expose prepare-shared "prepare-shared")
(expose cast-shared "cast-shared")
(expose cast "cast")
(expose probe-wall "probe-wall")
(expose prepare-grid "prepare-grid")
(expose grid-open? "grid-open")
(expose grid-hub "grid-hub")
(expose grid-distance "grid-distance")
(expose shipping-field! "shipping-field")
(expose packed-field! "packed-field")
(expose enable-profile! "enable-profile")
(expose allocation-count "allocations")
(expose collection-count "collections")
