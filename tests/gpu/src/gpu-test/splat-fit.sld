;; Densification on the device, of four live gaussians: a small one with
;; a large screen-space gradient is cloned, a large one split into two
;; children, a faint one pruned, and a still one kept, the kept first and
;; the new after them, in a cloud of capacity 8; and in one of capacity 4,
;; whose room the clone takes, so the large one stays whole.
(define-library (gpu-test splat-fit)
  (export
   splat-densify-check
   splat-room-check)
  (import
   (snail core base)
   (only (snail shell task) tasks)
   (only (snail shell gpu) Gpu)
   (only (snail shell math) log)
   (rename (snail shell tensor)
           (log tensor-log))
   (only (snail shell tensor eval) bytes->values values->bytes)
   (snail shell tensor compile)
   (snail shell graphics splat-train)
   (snail shell graphics splat-fit))
  (begin

    (define (floats (values (List F64))) (→ Bytes) (values->bytes (list->array values) (Float)))

    (define (zeros (count I64)) (→ (List F64)) (map (lambda (_) 0.0) (iota count)))

    (define small (→ F64) (log 0.005))

    (define large (→ F64) (log 0.05))

    ;; Each gaussian's row, then zero rows to the capacity.
    (define (rows (capacity I64) (each (List (List F64))) (width I64)) (→ (List F64))
      (append (concatenate each) (zeros (* width (- capacity (length each))))))

    ;; What densifying the four leaves in a cloud of `capacity`.
    (record Densified
      ((live (List F64))
       (means (Array F64))
       (scales (Array F64))
       (count F64)))

    (define (densified-in (gpu Gpu) (capacity I64)) (→ Densified) (! mut tasks)
      (let* ((cloud (splat-params capacity))
             (densified (densification cloud (stats-params capacity)))
             (program
              (compile-program gpu "densify" (list (● densified second)) (● densified first)))
             (padded (lambda (each width) (rows capacity each width))))
        (for-each (lambda (pair) (write-param gpu program (● pair first) (floats (● pair second))))
                  (list (new Pair
                          (first "means")
                          (second (padded (list (list 1.0 0.0 0.0)
                                                (list 0.0 2.0 0.0)
                                                (list 0.0 0.0 3.0)
                                                (list 4.0 4.0 4.0))
                                          3)))
                        (new Pair
                          (first "scales")
                          (second (padded (list (list small small small)
                                                (list large large large)
                                                (list small small small)
                                                (list small small small))
                                          3)))
                        (new Pair
                          (first "rotations")
                          (second (padded (map (lambda (_) (list 0.0 0.0 0.0 1.0)) (iota 4)) 4)))
                        (new Pair
                          (first "opacities")
                          (second (padded (list (list 0.0) (list 0.0) (list -6.0) (list 0.0)) 1)))
                        (new Pair
                          (first "live")
                          (second (padded (map (lambda (_) (list 1.0)) (iota 4)) 1)))
                        (new Pair
                          (first "gradient-sums")
                          (second
                           (padded (list (list 0.001) (list 0.001) (list 0.001) (list 0.0)) 1)))
                        (new Pair
                          (first "views-seen")
                          (second (padded (map (lambda (_) (list 1.0)) (iota 4)) 1)))
                        (new Pair (first "extent") (second (list 1.0)))
                        (new Pair (first "prune-big") (second (list 0.0)))))
        (write-param gpu program "seed" (values->bytes (list->array (list 12345.0)) (Unsigned)))
        (run-program gpu program)
        (let ((d (new Densified
                   (live (array->list (bytes->values (read-param gpu program "live") (Float))))
                   (means (bytes->values (read-param gpu program "means") (Float)))
                   (scales (bytes->values (read-param gpu program "scales") (Float)))
                   (count (array-ref (bytes->values (read-sink gpu program 0) (Float)) 0)))))
          (release-program gpu program)
          d)))

    (define (mean-at (d Densified) (slot I64)) (→ (List F64))
      (map (lambda (k) (array-ref (● d means) (+ (* 3 slot) k))) (iota 3)))

    (define (live-text (d Densified)) (→ String)
      (string-append "live "
                     (string-join (map (lambda (v) (show (f64->i64 v))) (● d live)) " ")
                     " ("
                     (show (f64->i64 (● d count)))
                     ")"))

    (define (splat-densify-check (gpu Gpu)) (→ String) (! mut tasks)
      (let* ((d (densified-in gpu 8))
             (mean (lambda (slot) (mean-at d slot)))
             (near (lambda (slot)
                     (every? (lambda (k)
                               (< (abs (- (list-ref (mean slot) k) (if (= k 1) 2.0 0.0))) 0.25))
                             (iota 3))))
             (child-scale (- large (log 1.6))))
        (string-append (live-text d)
                       (if (and (equal-means? (mean 0) (list 1.0 0.0 0.0))
                                (equal-means? (mean 1) (list 4.0 4.0 4.0))
                                (equal-means? (mean 2) (list 1.0 0.0 0.0)))
                           ", kept then cloned"
                           ", misplaced")
                       (if (and (near 3) (near 4) (not (equal-means? (mean 3) (mean 4)))
                                (< (abs (- (array-ref (● d scales) 9) child-scale)) 0.0001)
                                (< (abs (- (array-ref (● d scales) 12) child-scale)) 0.0001))
                           ", two children 1.6 times smaller"
                           ", children wrong"))))

    ;; Three stay, so a cloud of 4 has room for one more row: the clone's,
    ;; whose row comes first. The large one is kept, unsplit.
    (define (splat-room-check (gpu Gpu)) (→ String) (! mut tasks)
      (let ((d (densified-in gpu 4)))
        (string-append (live-text d)
                       (if (and (equal-means? (mean-at d 0) (list 1.0 0.0 0.0))
                                (equal-means? (mean-at d 1) (list 0.0 2.0 0.0))
                                (equal-means? (mean-at d 2) (list 4.0 4.0 4.0))
                                (equal-means? (mean-at d 3) (list 1.0 0.0 0.0))
                                (< (abs (- (array-ref (● d scales) 3) large)) 0.0001))
                           ", cloned, the large one kept whole"
                           ", misplaced"))))

    (define (equal-means? (a (List F64)) (b (List F64))) (→ Bool)
      (every? (lambda (pair) (< (abs (- (● pair first) (● pair second))) 0.000001)) (zip a b)))

    ))
