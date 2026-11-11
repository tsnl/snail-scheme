;; The map grid: cells, distances, the cells a straight line crosses, the
;; fewest closed cells joining two places, and breadth-first distance
;; fields.
(define-library (siegework grid)
  (export
   map-size
   Cell
   cell=?
   cell-index
   index-cell
   in-bounds?
   distance-squared
   manhattan
   within?
   integer-sqrt
   neighbors
   line-cells
   crossing-path
   distance-field)
  (import
   (snail core base)
   (snail shell wire))
  (begin

    ;; ---- Cells ----

    (define map-size (→ I64) 80)

    (struct Cell
      ((x I64)
       (y I64))
      (deriving Serialize Deserialize))

    (define (cell=? (a Cell) (b Cell)) (→ Bool)
      (and (= (::x a) (::x b)) (= (::y a) (::y b))))

    (define (cell-index (cell Cell)) (→ I64)
      (+ (::x cell) (* map-size (::y cell))))

    (define (index-cell (index I64)) (→ Cell)
      (Cell (remainder index map-size) (quotient index map-size)))

    (define (in-bounds? (cell Cell)) (→ Bool)
      (and (<= 0 (::x cell))
           (< (::x cell) map-size)
           (<= 0 (::y cell))
           (< (::y cell) map-size)))

    (define (distance-squared (a Cell) (b Cell)) (→ I64)
      (let ((dx (- (::x a) (::x b))) (dy (- (::y a) (::y b))))
        (+ (* dx dx) (* dy dy))))

    (define (manhattan (a Cell) (b Cell)) (→ I64)
      (+ (abs (- (::x a) (::x b))) (abs (- (::y a) (::y b)))))

    ;; Within a circle of `radius` cells around `center`.
    (define (within? (cell Cell) (center Cell) (radius I64)) (→ Bool)
      (<= (distance-squared cell center) (* radius radius)))

    ;; The largest integer whose square is at most `square`, by Newton's
    ;; iteration from above.
    (define (integer-sqrt (square I64)) (→ I64)
      (if (= square 0)
          0
          (let loop ((guess square))
            (let ((next (quotient (+ guess (quotient square guess)) 2)))
              (if (>= next guess) guess (loop next))))))

    ;; East, west, south, north: a fixed order, so ties break the same way.
    (define (neighbors (cell Cell)) (→ (List Cell))
      (let ((x (::x cell)) (y (::y cell)))
        (filter in-bounds?
                (list (Cell (+ x 1) y) (Cell (- x 1) y) (Cell x (+ y 1)) (Cell x (- y 1))))))

    ;; ---- Straight lines ----

    ;; Every cell the segment between two cell centers touches, from `a` to
    ;; `b`. In half-cell units the next vertical grid line is `nx` away along
    ;; x and the next horizontal one `ny` along y, so the segment meets the
    ;; horizontal line first exactly when `ny * dx < nx * dy`. A segment
    ;; along an axis never meets the other kind of line, and one through a
    ;; corner touches both side cells, so nothing is seen or wired diagonally
    ;; between two rocks.
    (define (line-cells (a Cell) (b Cell)) (→ (List Cell))
      (let ((dx (abs (- (::x b) (::x a)))) (dy (abs (- (::y b) (::y a))))
            (sx (if (< (::x a) (::x b)) 1 -1)) (sy (if (< (::y a) (::y b)) 1 -1)))
        (let walk ((x (::x a)) (y (::y a)) (nx 1) (ny 1) (cells (Nil)))
          (let ((cells (Cons (Cell x y) cells)) (order (- (* ny dx) (* nx dy))))
            (cond ((and (= x (::x b)) (= y (::y b))) (reverse cells))
                  ((< order 0) (walk x (+ y sy) nx (+ ny 2) cells))
                  ((> order 0) (walk (+ x sx) y (+ nx 2) ny cells))
                  (else (walk (+ x sx)
                              (+ y sy)
                              (+ nx 2)
                              (+ ny 2)
                              (Cons (Cell x (+ y sy)) (Cons (Cell (+ x sx) y) cells)))))))))

    ;; ---- Passes ----

    ;; The closed cells on a way from `start` to the nearest goal that
    ;; crosses as few of them as possible: opening them joins the two. The
    ;; search grows from the goals in rounds. Round k reaches every cell
    ;; whose best way crosses k closed cells, spreading through open cells
    ;; within the round and into closed ones for the next. Each cell keeps
    ;; the neighbor it was reached from, so the way is read back from
    ;; `start`. The array is local to the search, so it is total.
    (define (crossing-path (open (Vector Bool)) (goals (List Cell)) (start Cell)) (→ (List Cell))
      (unsafe-total
       (lambda ()
         (let ((from (make-array (* map-size map-size) -1)))
           (for-each (lambda (goal) (array-set! from (cell-index goal) (cell-index goal))) goals)
           (let round ((current goals) (next (Nil)))
             (match current
               ((Nil) (if (null? next)
                          (let back ((index (cell-index start)) (closed (Nil)))
                            (let ((closed (if (vector-ref open index)
                                              closed
                                              (Cons (index-cell index) closed))))
                              (if (= (array-ref from index) index)
                                  closed
                                  (back (array-ref from index) closed))))
                          (round next (Nil))))
               ((Cons cell rest)
                (let ((reached (filter (lambda (n) (= (array-ref from (cell-index n)) -1))
                                       (neighbors cell))))
                  (for-each (lambda (n) (array-set! from (cell-index n) (cell-index cell))) reached)
                  (round
                   (append (filter (lambda (n) (vector-ref open (cell-index n))) reached) rest)
                   (append (filter (lambda (n) (not (vector-ref open (cell-index n)))) reached)
                           next))))))))))

    ;; ---- Distance fields ----

    ;; The number of steps from each cell to the nearest goal, moving through
    ;; open cells, or -1 where no goal can be reached. A walker heads for a
    ;; goal by stepping to any neighbor one step closer. The array is local
    ;; to the search, so it is total.
    (define (distance-field (open (Vector Bool)) (goals (List Cell))) (→ (Vector I64))
      (unsafe-total
       (lambda ()
         (let ((distance (make-array (* map-size map-size) -1)))
           (for-each (lambda (goal) (array-set! distance (cell-index goal) 0)) goals)
           (let loop ((frontier goals) (next (Nil)))
             (match frontier
               ((Nil) (if (null? next) (array->vector distance) (loop (reverse next) (Nil))))
               ((Cons cell rest)
                (let ((steps (+ (array-ref distance (cell-index cell)) 1)))
                  (loop rest (fold-left (lambda (queued neighbor)
                                          (let ((index (cell-index neighbor)))
                                            (if (and (vector-ref open index)
                                                     (= (array-ref distance index) -1))
                                                (begin
                                                  (array-set! distance index steps)
                                                  (Cons neighbor queued))
                                                queued)))
                                        next (neighbors cell)))))))))))

    ))
