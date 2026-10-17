;; Fixed geography and shortest walking routes. Search mutates only fresh scratch
;; vectors; returned paths and remembered surveys are immutable world values.
(define-library (siegework terrain)
  (export map-width map-height hub-x hub-y cell-size cell-x cell-y cell-index
          index-x index-y inside? ground? deposit-rate distance within?
          Survey make-survey survey-x survey-y survey-radius surveyed?
          walking-path)
  (import (scheme base)
          (scheme immutable)
          (only (lofi core) ann I32)
          (only (lofi base) i32->i64))
  (begin

    ;; ---- Fixed terrain ----

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
    (define (ground? x y)
      (and (inside? x y)
           (not (and (>= x 23) (<= x 24) (< y 31) (or (< y 16) (> y 19))))
           (not (and (= y 10) (< x 19) (or (< x 10) (> x 13))))
           (not (and (>= x 32) (<= x 38) (>= y 25) (<= y 28)))))
    (define (deposit-rate x y)
      (cond ((and (= x 12) (= y 20)) 2)
            ((and (= x 5) (= y 5)) 3)
            ((and (= x 36) (= y 12)) 6)
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
    (define (visit-cell! previous queue tail from x y surveys unrestricted)
      (if (and (ground? x y) (= (read-cell previous (cell-index x y)) -1)
               (or unrestricted (surveyed? surveys x y)))
          (let ((index (cell-index x y)))
            (write-cell! previous index from)
            (write-cell! queue tail index)
            (+ tail 1)) tail))
    (define (visit-neighbors! previous queue tail from surveys unrestricted)
      (let* ((x (index-x from)) (y (index-y from))
             (tail (visit-cell! previous queue tail from (+ x 1) y surveys unrestricted))
             (tail (visit-cell! previous queue tail from (- x 1) y surveys unrestricted))
             (tail (visit-cell! previous queue tail from x (+ y 1) surveys unrestricted)))
        (visit-cell! previous queue tail from x (- y 1) surveys unrestricted)))
    (define (search-route! previous queue head tail target surveys unrestricted)
      (when (and (< head tail) (= (read-cell previous target) -1))
        (let ((tail (visit-neighbors! previous queue tail (read-cell queue head) surveys unrestricted)))
          (search-route! previous queue (+ head 1) tail target surveys unrestricted))))
    (define (route-back previous start current route)
      (if (= current start) route
          (route-back previous start (read-cell previous current) (cons current route))))
    (define (walking-path x y a b surveys unrestricted)
      (let* ((start (cell-index x y)) (target (cell-index a b))
             (previous (make-vector (i32->i64 (* map-width map-height)) -1))
             (queue (make-vector (i32->i64 (* map-width map-height)) 0)))
        (write-cell! previous start start)
        (write-cell! queue 0 start)
        (search-route! previous queue 0 1 target surveys unrestricted)
        (if (= (read-cell previous target) -1) (empty-list)
            (route-back previous start target (empty-list)))))))
