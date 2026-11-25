;; The map grid: cells, distances, the cells a straight line crosses, the
;; fewest closed cells joining two places, and breadth-first distance
;; fields.
(define-library (apps siegework grid)
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
   PathQueue
   make-path-queue
   search-distances
   distance-field)
  (import
   (snail core base)
   (snail shell wire))
  (begin

    ;; ---- Cells ----

    (define map-size (→ I64) 80)

    (record Cell
      ((x I64)
       (y I64))
      (deriving Serialize Deserialize))

    (define (cell=? (a Cell) (b Cell)) (→ Bool)
      (and (= (● a x) (● b x)) (= (● a y) (● b y))))

    (define (cell-index (cell Cell)) (→ I64)
      (+ (● cell x) (* map-size (● cell y))))

    (define (index-cell (index I64)) (→ Cell)
      (new Cell (x (remainder index map-size)) (y (quotient index map-size))))

    (define (in-bounds? (cell Cell)) (→ Bool)
      (and (<= 0 (● cell x))
           (< (● cell x) map-size)
           (<= 0 (● cell y))
           (< (● cell y) map-size)))

    (define (distance-squared (a Cell) (b Cell)) (→ I64)
      (let ((dx (- (● a x) (● b x))) (dy (- (● a y) (● b y))))
        (+ (* dx dx) (* dy dy))))

    (define (manhattan (a Cell) (b Cell)) (→ I64)
      (+ (abs (- (● a x) (● b x))) (abs (- (● a y) (● b y)))))

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
      (let ((x (● cell x)) (y (● cell y)))
        (filter in-bounds?
                (list (new Cell (x (+ x 1)) (y y))
                      (new Cell (x (- x 1)) (y y))
                      (new Cell (x x) (y (+ y 1)))
                      (new Cell (x x) (y (- y 1)))))))

    ;; ---- Straight lines ----

    ;; Every cell the segment between two cell centers touches, from `a` to
    ;; `b`. In half-cell units the next vertical grid line is `nx` away along
    ;; x and the next horizontal one `ny` along y, so the segment meets the
    ;; horizontal line first exactly when `ny * dx < nx * dy`. A segment
    ;; along an axis never meets the other kind of line, and one through a
    ;; corner touches both side cells, so nothing is seen or wired diagonally
    ;; between two rocks.
    (define (line-cells (a Cell) (b Cell)) (→ (List Cell))
      (let ((dx (abs (- (● b x) (● a x)))) (dy (abs (- (● b y) (● a y))))
            (sx (if (< (● a x) (● b x)) 1 -1)) (sy (if (< (● a y) (● b y)) 1 -1)))
        (let walk ((x (● a x)) (y (● a y)) (nx 1) (ny 1) (cells (Nil)))
          (let ((cells (Cons (new Cell (x x) (y y)) cells)) (order (- (* ny dx) (* nx dy))))
            (cond ((and (= x (● b x)) (= y (● b y))) (reverse cells))
                  ((< order 0) (walk x (+ y sy) nx (+ ny 2) cells))
                  ((> order 0) (walk (+ x sx) y (+ nx 2) ny cells))
                  (else (walk (+ x sx)
                              (+ y sy)
                              (+ nx 2)
                              (+ ny 2)
                              (Cons (new Cell (x x) (y (+ y sy)))
                                    (Cons (new Cell (x (+ x sx)) (y y)) cells)))))))))

    ;; ---- Passes ----

    ;; The closed cells on a way from `start` to the nearest goal that
    ;; crosses as few of them as possible: opening them joins the two. The
    ;; search grows from the goals in rounds. Round k reaches every cell
    ;; whose best way crosses k closed cells, spreading through open cells
    ;; within the round and into closed ones for the next. Each cell keeps
    ;; the neighbor it was reached from, so the way is read back from
    ;; `start`. The array is the search's own.
    (define (crossing-path (open (Array Bool)) (goals (List Cell)) (start Cell)) (→ (List Cell))
      (let ((from (make-array (* map-size map-size) -1)))
        (for-each (lambda (goal)
                    (array-set!
                     from
                     (cell-index goal)
                     (cell-index goal)))
                  goals)
        (let round ((current goals) (next (Nil)))
          (match current
            ((Nil) (if (null? next)
                       (let back ((index (cell-index start))
                                  (closed (Nil)))
                         (let ((closed (if (array-ref open index)
                                           closed
                                           (Cons (index-cell index)
                                                 closed))))
                           (if (= (array-ref from index) index)
                               closed
                               (back (array-ref from index) closed))))
                       (round next (Nil))))
            ((Cons cell rest)
             (let ((reached (filter (lambda (n)
                                      (= (array-ref from (cell-index n))
                                         -1))
                                    (neighbors cell))))
               (for-each (lambda (n)
                           (array-set!
                            from
                            (cell-index n)
                            (cell-index cell)))
                         reached)
               (round
                (append
                 (filter (lambda (n) (array-ref open (cell-index n)))
                         reached)
                 rest)
                (append (filter (lambda (n)
                                  (not (array-ref open (cell-index n))))
                                reached)
                        next))))))))

    ;; ---- Distance fields ----

    ;; A map owns one FIFO of cell indices. A search finishes synchronously.
    ;; Several routes may keep their answers after the next search starts.
    (record PathQueue
      ((slots (Array I64))))

    (define (make-path-queue) (→ PathQueue)
      (new PathQueue (slots (make-array (* map-size map-size) 0))))

    (record Search
      ((open (Array Bool))
       (distance (Array I64))
       (queue (Array I64))))

    ;; Mark on enqueue, including duplicate goals. Each cell occupies at
    ;; most one slot, so a full map fits even when every cell is a goal.
    (define (enqueue! (search Search) (cell I64) (steps I64) (end I64)) (→ I64)
      (if (= (array-ref (● search distance) cell) -1)
          (begin (array-set! (● search distance) cell steps)
                 (array-set! (● search queue) end cell)
                 (+ end 1))
          end))

    (define (reach! (search Search) (cell I64) (steps I64) (end I64)) (→ I64)
      (if (array-ref (● search open) cell) (enqueue! search cell steps end) end))

    (define (expand! (search Search) (cell I64) (end I64)) (→ I64)
      (let* ((steps (+ 1 (array-ref (● search distance) cell))) (x (remainder cell map-size))
             (end (if (< (+ x 1) map-size) (reach! search (+ cell 1) steps end) end))
             (end (if (> x 0) (reach! search (- cell 1) steps end) end))
             (end (if (< (+ cell map-size) (* map-size map-size))
                      (reach! search (+ cell map-size) steps end) end)))
        (if (>= cell map-size) (reach! search (- cell map-size) steps end) end)))

    ;; Each in-bounds goal starts at zero, even on closed ground. Neighbors
    ;; must be open. Unreachable cells keep -1 in the caller's fresh field.
    (define (search-distances (paths PathQueue) (open (Array Bool)) (goals (List Cell)))
      (→ (Array I64))
      (let* ((distance (make-array (* map-size map-size) -1))
             (search (new Search (open open) (distance distance) (queue (● paths slots))))
             (seeds (fold-left (lambda (end goal) (enqueue! search (cell-index goal) 0 end))
                               0 goals)))
        (let visit ((head 0) (end seeds))
          (if (= head end) distance
              (visit (+ head 1) (expand! search (array-ref (● paths slots) head) end))))))

    (define (distance-field (open (Array Bool)) (goals (List Cell))) (→ (Array I64))
      (search-distances (make-path-queue) open goals))))
