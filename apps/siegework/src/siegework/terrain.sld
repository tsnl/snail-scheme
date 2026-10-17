;; The saved seed selects bounded geography; no map generation retries are needed.
;; Search mutates fresh scratch vectors, never the world's surveys or hazards.
(define-library (siegework terrain)
  (export map-width map-height hub-x hub-y cell-size cell-x cell-y cell-index
          index-x index-y inside? ground? deposit-rate distance within?
          Survey make-survey survey-x survey-y survey-radius surveyed?
          next-map-seed northern-x northern-y eastern-x eastern-y
          walking-path avoiding-path escape-path)
  (import (scheme base)
          (scheme immutable)
          (only (lofi core) I32)
          (only (lofi base) i32->i64))
  (begin

    ;; ---- Map coordinates ----

    (define map-width 48)
    (define map-height 36)
    (define cell-size 40)
    (define hub-x 8)
    (define hub-y 22)
    (define (cell-x x) (+ (* x cell-size) 20))
    (define (cell-y y) (+ (* y cell-size) 20))
    (define (cell-index x y) (+ x (* y map-width)))
    (define (index-x index) (remainder index map-width))
    (define (index-y index) (quotient index map-width))
    (define (inside? x y) (and (>= x 0) (< x map-width) (>= y 0) (< y map-height)))
    (define (absolute value) (if (< value 0) (- 0 value) value))
    (define (distance x y a b) (+ (absolute (- x a)) (absolute (- y b))))
    (define (within? x y a b radius)
      (<= (+ (* (- x a) (- x a)) (* (- y b) (- y b))) (* radius radius)))

    ;; ---- Seeded geography ----

    ;; Seeds are stored as 1..65535. Different strides vary each bounded
    ;; feature without mutable random state; the largest product fits in I32.
    ;; Seed 1 preserves every cell of the original map, including wider gaps.
    (define (next-map-seed seed)
      (if (or (< seed 1) (>= seed 65535)) 1 (+ seed 1)))
    (define (map-offset seed stride count)
      (remainder (remainder (* seed stride) 65521) count))
    (define (northern-x seed) (if (= seed 1) 5 (+ 4 (map-offset seed 73 11))))
    (define (northern-y seed) (if (= seed 1) 5 (+ 3 (map-offset seed 151 4))))
    (define (eastern-x seed) (if (= seed 1) 36 (+ 33 (map-offset seed 199 9))))
    (define (eastern-y seed) (if (= seed 1) 12 (+ 7 (map-offset seed 239 10))))

    ;; The ridge stays east of the hub and starter. Its crossing is at least
    ;; three cells tall, and the southern edge remains a second way around it.
    (define (ridge? seed x y)
      (let ((left (if (= seed 1) 23 (+ 22 (map-offset seed 31 5))))
            (opening (if (= seed 1) 16 (+ 15 (map-offset seed 43 7))))
            (height (if (= seed 1) 4 3)))
        (and (>= x left) (<= x (+ left 1)) (< y 31)
             (or (< y opening) (>= y (+ opening height))))))
    ;; The northern mine is above this wall. Both its gap and the open strip
    ;; at x=19..21 connect it to the hub, regardless of the chosen ridge.
    (define (northern-wall? seed x y)
      (let ((row (if (= seed 1) 10 (+ 9 (map-offset seed 59 4))))
            (opening (if (= seed 1) 10 (+ 8 (map-offset seed 83 7))))
            (width (if (= seed 1) 4 3)))
        (and (= y row) (< x 19)
             (or (< x opening) (>= x (+ opening width))))))
    ;; This isolated rock bed stays below the eastern mine and beyond the
    ;; ridge crossing. All its edges leave room to walk around it.
    (define (southern-rock? seed x y)
      (let ((left (if (= seed 1) 32 (+ 31 (map-offset seed 107 7))))
            (top (if (= seed 1) 25 (+ 24 (map-offset seed 127 5)))))
        (and (>= x left) (<= x (+ left 6)) (>= y top) (<= y (+ top 3)))))
    (define (ground? seed x y)
      (and (inside? x y)
           (not (ridge? seed x y))
           (not (northern-wall? seed x y))
           (not (southern-rock? seed x y))))
    (define (deposit-rate seed x y)
      (cond ((and (= x 12) (= y 20)) 2)
            ((and (= x (northern-x seed)) (= y (northern-y seed))) 3)
            ((and (= x (eastern-x seed)) (= y (eastern-y seed))) 6)
            (else 0)))

    ;; ---- Geography remains known after observation is lost ----

    (define-immutable-record Survey make-survey
      (x I32 survey-x survey-x-set)
      (y I32 survey-y survey-y-set)
      (radius I32 survey-radius survey-radius-set))
    (define (surveyed? surveys x y)
      (and (not (null? surveys))
           (or (within? x y (survey-x (car surveys)) (survey-y (car surveys))
                        (survey-radius (car surveys)))
               (surveyed? (cdr surveys) x y))))

    ;; ---- Breadth-first search produces an adjacent-cell route ----

    (define (read-cell cells index) (vector-ref cells (i32->i64 index)))
    (define (write-cell! cells index value) (vector-set! cells (i32->i64 index) value))
    (define (visit-cell! seed previous queue tail from x y surveys hazards unrestricted)
      (if (and (ground? seed x y) (= (read-cell previous (cell-index x y)) -1)
               (or unrestricted (surveyed? surveys x y))
               (not (surveyed? hazards x y)))
          (let ((index (cell-index x y)))
            (write-cell! previous index from)
            (write-cell! queue tail index)
            (+ tail 1)) tail))
    (define (visit-neighbors! seed previous queue tail from surveys hazards unrestricted)
      (let* ((x (index-x from)) (y (index-y from))
             (tail (visit-cell! seed previous queue tail from (+ x 1) y surveys hazards unrestricted))
             (tail (visit-cell! seed previous queue tail from (- x 1) y surveys hazards unrestricted))
             (tail (visit-cell! seed previous queue tail from x (+ y 1) surveys hazards unrestricted)))
        (visit-cell! seed previous queue tail from x (- y 1) surveys hazards unrestricted)))
    (define (search-route! seed previous queue head tail target surveys hazards unrestricted)
      (when (and (< head tail) (= (read-cell previous target) -1))
        (let ((tail (visit-neighbors! seed previous queue tail (read-cell queue head)
                                      surveys hazards unrestricted)))
          (search-route! seed previous queue (+ head 1) tail target surveys hazards unrestricted))))
    (define (route-back previous start current route)
      (if (= current start) route
          (route-back previous start (read-cell previous current) (cons current route))))
    ;; Marking on enqueue bounds both scratch vectors to one entry per cell.
    ;; Only the starting cell may be hazardous: a safe adjacent cell permits
    ;; departure, but an enclosed start needs the worker's separate flee step.
    (define (find-path seed x y a b surveys hazards unrestricted)
      (if (not (and (ground? seed x y) (ground? seed a b))) (empty-list)
          (let* ((start (cell-index x y)) (target (cell-index a b))
                 (previous (make-vector (i32->i64 (* map-width map-height)) -1))
                 (queue (make-vector (i32->i64 (* map-width map-height)) 0)))
            (write-cell! previous start start)
            (write-cell! queue 0 start)
            (search-route! seed previous queue 0 1 target surveys hazards unrestricted)
            (if (= (read-cell previous target) -1) (empty-list)
                (route-back previous start target (empty-list))))))
    (define (walking-path seed x y a b surveys unrestricted)
      (find-path seed x y a b surveys (empty-list) unrestricted))
    (define (avoiding-path seed x y a b surveys hazards)
      (find-path seed x y a b surveys hazards #f))


    ;; Emergency escape may cross the warning radius, but never an occupied
    ;; enemy cell. BFS finds a nearby safe cell and permits lateral movement
    ;; around walls; forbidding the entire radius would trap its own start.
    (define (occupied-hazards hazards)
      (if (null? hazards) (empty-list)
          (cons (make-survey (survey-x (car hazards)) (survey-y (car hazards)) 0)
                (occupied-hazards (cdr hazards)))))
    (define (search-escape! seed previous queue head tail surveys hazards occupied)
      (if (= head tail) -1
          (let ((cell (read-cell queue head)))
            (if (not (surveyed? hazards (index-x cell) (index-y cell))) cell
                (search-escape! seed previous queue (+ head 1)
                                (visit-neighbors! seed previous queue tail cell surveys occupied #f)
                                surveys hazards occupied)))))
    (define (escape-path seed x y surveys hazards)
      (let* ((start (cell-index x y))
             (previous (make-vector (i32->i64 (* map-width map-height)) -1))
             (queue (make-vector (i32->i64 (* map-width map-height)) 0)))
        (write-cell! previous start start)
        (write-cell! queue 0 start)
        (let ((target (search-escape! seed previous queue 0 1 surveys hazards (occupied-hazards hazards))))
          (if (< target 0) (empty-list) (route-back previous start target (empty-list))))))))
