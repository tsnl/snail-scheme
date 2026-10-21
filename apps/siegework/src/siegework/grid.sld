;; The map grid: cells, distances and shortest walking paths.
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
   adjacent?
   neighbors
   find-path
   reachable)
  (import
   (lofi base)
   (lofi wire))
  (begin

    ;; ---- Cells ----

    (: map-size I64)
    (define map-size 40)

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

    ;; Touching, including diagonally.
    (: adjacent? (-> Cell Cell Bool))
    (define (adjacent? a b)
      (<= (distance-squared a b) 2))

    (: neighbors (-> Cell (List Cell)))
    (define (neighbors cell)
      (let ((x (Cell-x cell)) (y (Cell-y cell)))
        (filter in-bounds? (list (Cell (+ x 1) y) (Cell (- x 1) y) (Cell x (+ y 1)) (Cell x (- y 1))))))

    ;; ---- Breadth-first search ----

    ;; Visits open cells from `start` in order of distance. `parent` records
    ;; each visited cell's predecessor; the search stops when `goal?` holds.
    ;; The arrays are local to the search, so it is total.
    (: search (-> (Vector Bool) Cell (-> Cell Bool) (Pair (Vector I64) (Option Cell))))
    (define (search open start goal?)
      (unsafe-total
       (lambda ()
         (let ((parent (make-array (* map-size map-size) -1)))
           (array-set! parent (cell-index start) (cell-index start))
           (let loop ((frontier (list start)) (next (Nil)))
             (match frontier
               ((Nil) (if (null? next)
                          (Pair (array->vector parent) (None))
                          (loop (reverse next) (Nil))))
               ((Cons cell rest)
                (if (goal? cell)
                    (Pair (array->vector parent) (Some cell))
                    (loop rest (fold-left (lambda (queued neighbor)
                                            (let ((index (cell-index neighbor)))
                                              (if (and (vector-ref open index) (= (array-ref parent index) -1))
                                                  (begin (array-set! parent index (cell-index cell)) (Cons neighbor queued))
                                                  queued)))
                                          next (neighbors cell)))))))))))

    ;; The cells to walk from `start` to a cell satisfying `goal?`,
    ;; excluding `start`. Only open cells are entered.
    (: find-path (-> (Vector Bool) Cell (-> Cell Bool) (Option (List Cell))))
    (define (find-path open start goal?)
      (match (search open start goal?)
        ((Pair parent (Some goal))
         (Some (let walk ((index (cell-index goal)) (path (Nil)))
                 (if (= index (cell-index start))
                     path
                     (walk (vector-ref parent index) (Cons (index-cell index) path))))))
        ((Pair _ (None)) (None))))

    ;; Whether each cell can be reached from `start`.
    (: reachable (-> (Vector Bool) Cell (Vector Bool)))
    (define (reachable open start)
      (match (search open start (lambda (cell) #f))
        ((Pair parent _) (vector-map (lambda (index) (>= index 0)) parent))))

    ))
