;; The map grid: cells, distances, the cells a straight line crosses, the
;; fewest closed cells joining two places, breadth-first distance fields,
;; and cost fields over a region of the map, where each cell costs its own
;; amount to enter.
(define-library (siegework grid)
  (export
   map-size
   Cell
   Cell-x
   Cell-y
   cell=?
   cell-index
   index-cell
   in-bounds?
   distance-squared
   manhattan
   within?
   beside?
   integer-sqrt
   neighbors
   line-cells
   crossing-path
   distance-field
   Region
   whole-map
   window
   Field
   Field-region
   Field-costs
   field-cost
   cost-field
   step-cost
   downhill)
  (import
   (lofi base)
   (lofi wire))
  (begin

    ;; ---- Cells ----

    (: map-size I64)
    (define map-size 80)

    (struct Cell
      ((x I64)
       (y I64))
      (deriving Serialize Deserialize))

    (: cell=? (-> Cell Cell Bool))
    (define (cell=? a b)
      (and (= (Cell-x a) (Cell-x b)) (= (Cell-y a) (Cell-y b))))

    (: cell-index (-> Cell I64))
    (define (cell-index cell)
      (+ (Cell-x cell) (* map-size (Cell-y cell))))

    (: index-cell (-> I64 Cell))
    (define (index-cell index)
      (Cell (remainder index map-size) (quotient index map-size)))

    (: in-bounds? (-> Cell Bool))
    (define (in-bounds? cell)
      (and (<= 0 (Cell-x cell)) (< (Cell-x cell) map-size) (<= 0 (Cell-y cell)) (< (Cell-y cell) map-size)))

    (: distance-squared (-> Cell Cell I64))
    (define (distance-squared a b)
      (let ((dx (- (Cell-x a) (Cell-x b))) (dy (- (Cell-y a) (Cell-y b))))
        (+ (* dx dx) (* dy dy))))

    (: manhattan (-> Cell Cell I64))
    (define (manhattan a b)
      (+ (abs (- (Cell-x a) (Cell-x b))) (abs (- (Cell-y a) (Cell-y b)))))

    ;; Within a circle of `radius` cells around `center`.
    (: within? (-> Cell Cell I64 Bool))
    (define (within? cell center radius)
      (<= (distance-squared cell center) (* radius radius)))

    ;; The same cell or one of its four neighbors.
    (: beside? (-> Cell Cell Bool))
    (define (beside? a b)
      (<= (distance-squared a b) 1))

    ;; The largest integer whose square is at most `square`, by Newton's
    ;; iteration from above.
    (: integer-sqrt (-> I64 I64))
    (define (integer-sqrt square)
      (if (= square 0)
          0
          (let loop ((guess square))
            (let ((next (quotient (+ guess (quotient square guess)) 2)))
              (if (>= next guess) guess (loop next))))))

    ;; East, west, south, north: a fixed order, so ties break the same way.
    (: neighbors (-> Cell (List Cell)))
    (define (neighbors cell)
      (let ((x (Cell-x cell)) (y (Cell-y cell)))
        (filter in-bounds? (list (Cell (+ x 1) y) (Cell (- x 1) y) (Cell x (+ y 1)) (Cell x (- y 1))))))

    ;; ---- Straight lines ----

    ;; Every cell the segment between two cell centers touches, from `a` to
    ;; `b`. In half-cell units the next vertical grid line is `nx` away along
    ;; x and the next horizontal one `ny` along y, so the segment meets the
    ;; horizontal line first exactly when `ny * dx < nx * dy`. A segment
    ;; along an axis never meets the other kind of line, and one through a
    ;; corner touches both side cells, so nothing is seen or wired diagonally
    ;; between two rocks.
    (: line-cells (-> Cell Cell (List Cell)))
    (define (line-cells a b)
      (let ((dx (abs (- (Cell-x b) (Cell-x a)))) (dy (abs (- (Cell-y b) (Cell-y a))))
            (sx (if (< (Cell-x a) (Cell-x b)) 1 -1)) (sy (if (< (Cell-y a) (Cell-y b)) 1 -1)))
        (let walk ((x (Cell-x a)) (y (Cell-y a)) (nx 1) (ny 1) (cells (Nil)))
          (let ((cells (Cons (Cell x y) cells)) (order (- (* ny dx) (* nx dy))))
            (cond ((and (= x (Cell-x b)) (= y (Cell-y b))) (reverse cells))
                  ((< order 0) (walk x (+ y sy) nx (+ ny 2) cells))
                  ((> order 0) (walk (+ x sx) y (+ nx 2) ny cells))
                  (else (walk (+ x sx) (+ y sy) (+ nx 2) (+ ny 2) (Cons (Cell x (+ y sy)) (Cons (Cell (+ x sx) y) cells)))))))))

    ;; ---- Passes ----

    ;; The closed cells on a way from `start` to the nearest goal that
    ;; crosses as few of them as possible: opening them joins the two. The
    ;; search grows from the goals in rounds. Round k reaches every cell
    ;; whose best way crosses k closed cells, spreading through open cells
    ;; within the round and into closed ones for the next. Each cell keeps
    ;; the neighbor it was reached from, so the way is read back from
    ;; `start`. The array is local to the search, so it is total.
    (: crossing-path (-> (Vector Bool) (List Cell) Cell (List Cell)))
    (define (crossing-path open goals start)
      (unsafe-total
       (lambda ()
         (let ((from (make-array (* map-size map-size) -1)))
           (for-each (lambda (goal) (array-set! from (cell-index goal) (cell-index goal))) goals)
           (let round ((current goals) (next (Nil)))
             (match current
               ((Nil) (if (null? next)
                          (let back ((index (cell-index start)) (closed (Nil)))
                            (let ((closed (if (vector-ref open index) closed (Cons (index-cell index) closed))))
                              (if (= (array-ref from index) index) closed (back (array-ref from index) closed))))
                          (round next (Nil))))
               ((Cons cell rest)
                (let ((reached (filter (lambda (n) (= (array-ref from (cell-index n)) -1)) (neighbors cell))))
                  (for-each (lambda (n) (array-set! from (cell-index n) (cell-index cell))) reached)
                  (round (append (filter (lambda (n) (vector-ref open (cell-index n))) reached) rest)
                         (append (filter (lambda (n) (not (vector-ref open (cell-index n)))) reached) next))))))))))

    ;; ---- Distance fields ----

    ;; The number of steps from each cell to the nearest goal, moving through
    ;; open cells, or -1 where no goal can be reached. A walker heads for a
    ;; goal by stepping to any neighbor one step closer. The array is local
    ;; to the search, so it is total.
    (: distance-field (-> (Vector Bool) (List Cell) (Vector I64)))
    (define (distance-field open goals)
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
                                            (if (and (vector-ref open index) (= (array-ref distance index) -1))
                                                (begin (array-set! distance index steps) (Cons neighbor queued))
                                                queued)))
                                        next (neighbors cell)))))))))))

    ;; ---- Cost fields ----

    ;; A rectangle of the map: the whole of it, or a window around a mover
    ;; for a search that never needs to look far.
    (struct Region
      ((x I64)
       (y I64)
       (width I64)
       (height I64)))

    (: whole-map Region)
    (define whole-map (Region 0 0 map-size map-size))

    ;; The square of `radius` cells around `center`, clipped to the map.
    (: window (-> Cell I64 Region))
    (define (window center radius)
      (let ((x (max 0 (- (Cell-x center) radius))) (y (max 0 (- (Cell-y center) radius))))
        (Region x y (- (min map-size (+ (Cell-x center) (+ radius 1))) x) (- (min map-size (+ (Cell-y center) (+ radius 1))) y))))

    (: inside? (-> Region Cell Bool))
    (define (inside? region cell)
      (and (<= (Region-x region) (Cell-x cell)) (< (Cell-x cell) (+ (Region-x region) (Region-width region)))
           (<= (Region-y region) (Cell-y cell)) (< (Cell-y cell) (+ (Region-y region) (Region-height region)))))

    (: region-index (-> Region Cell I64))
    (define (region-index region cell)
      (+ (- (Cell-x cell) (Region-x region)) (* (Region-width region) (- (Cell-y cell) (Region-y region)))))

    (: region-cell (-> Region I64 Cell))
    (define (region-cell region index)
      (Cell (+ (Region-x region) (remainder index (Region-width region))) (+ (Region-y region) (quotient index (Region-width region)))))

    ;; The least cost from each cell of a region to the nearest goal, or -1
    ;; where none can be reached inside it.
    (struct Field
      ((region Region)
       (costs (Vector I64))))

    (: field-cost (-> Field Cell I64))
    (define (field-cost field cell)
      (if (inside? (Field-region field) cell) (vector-ref (Field-costs field) (region-index (Field-region field) cell)) -1))

    ;; What stepping onto `cell` adds: what `enter` asks, which is -1 for a
    ;; cell that cannot be entered. A goal that cannot be entered, such as
    ;; a wall to be worked on, still costs one step to reach beside.
    (: step-cost (-> (-> Cell I64) Cell Bool I64))
    (define (step-cost enter cell goal)
      (let ((cost (enter cell)))
        (if (and (< cost 0) goal) 1 cost)))

    ;; Dijkstra's search from the goals outward, over a binary heap of
    ;; costs packed with the cell's index in the region: the cost times 8192
    ;; plus an index below 6400, so comparing packed values compares costs
    ;; first. A cell may be queued more than once; a stale entry, costlier
    ;; than the cell's best, is skipped. Each cell enters the heap at most
    ;; once per neighbor, which bounds its size. The arrays are local to
    ;; the search, so it is total.
    (: cost-field (-> Region (-> Cell I64) (List Cell) Field))
    (define (cost-field region enter goals)
      (unsafe-total
       (lambda ()
         (let* ((size (* (Region-width region) (Region-height region))) (best (make-array size -1))
                (heap (make-array (+ (* 4 size) (+ (length goals) 1)) 0)) (count (ref 0)))
           (for-each (lambda (goal)
                       (when (inside? region goal)
                         (array-set! best (region-index region goal) 0)
                         (heap-push! heap count (region-index region goal))))
                     goals)
           (let loop ((pending (ref-get count)))
             (if (= pending 0)
                 (Field region (array->vector best))
                 (let* ((top (heap-pop! heap count)) (cost (quotient top 8192)) (index (remainder top 8192)))
                   (when (= cost (array-ref best index))
                     (relax! region enter best heap count (region-cell region index) cost))
                   (loop (ref-get count)))))))))

    ;; Offers each neighbor of a settled cell the way through it.
    (: relax! (-> Region (-> Cell I64) (Array I64) (Array I64) (Ref I64) Cell I64 Unit ! mut))
    (define (relax! region enter best heap count cell cost)
      (let ((step (step-cost enter cell (= cost 0))))
        (when (>= step 0)
          (for-each (lambda (n)
                      (when (inside? region n)
                        (let ((index (region-index region n)) (through (+ cost step)))
                          (when (or (< (array-ref best index) 0) (< through (array-ref best index)))
                            (array-set! best index through)
                            (heap-push! heap count (+ (* through 8192) index))))))
                    (neighbors cell)))))

    (: heap-push! (-> (Array I64) (Ref I64) I64 Unit ! mut))
    (define (heap-push! heap count value)
      (let ((index (ref-get count)))
        (ref-set! count (+ index 1))
        (sift-up! heap index value)))

    (: sift-up! (-> (Array I64) I64 I64 Unit ! mut))
    (define (sift-up! heap index value)
      (let ((parent (quotient (- index 1) 2)))
        (if (and (> index 0) (< value (array-ref heap parent)))
            (begin (array-set! heap index (array-ref heap parent))
                   (sift-up! heap parent value))
            (array-set! heap index value))))

    (: heap-pop! (-> (Array I64) (Ref I64) I64 ! mut))
    (define (heap-pop! heap count)
      (let ((top (array-ref heap 0)) (size (- (ref-get count) 1)))
        (ref-set! count size)
        (when (> size 0)
          (sift-down! heap size 0 (array-ref heap size)))
        top))

    (: sift-down! (-> (Array I64) I64 I64 I64 Unit ! mut))
    (define (sift-down! heap size index value)
      (let* ((left (+ 1 (* 2 index))) (right (+ left 1))
             (child (if (and (< right size) (< (array-ref heap right) (array-ref heap left))) right left)))
        (if (and (< left size) (< (array-ref heap child) value))
            (begin (array-set! heap index (array-ref heap child))
                   (sift-down! heap size child value))
            (array-set! heap index value))))

    ;; The neighbors one step along a cheapest way to the goal: those whose
    ;; cost plus the cost of stepping onto them is the cost here. Empty at
    ;; a goal and where no goal can be reached.
    (: downhill (-> Field (-> Cell I64) Cell (List Cell)))
    (define (downhill field enter cell)
      (let ((here (field-cost field cell)))
        (filter (lambda (n)
                  (let ((there (field-cost field n)))
                    (and (> here 0) (>= there 0)
                         (let ((step (step-cost enter n (= there 0)))) (and (>= step 0) (= here (+ there step)))))))
                (neighbors cell))))

    ))
