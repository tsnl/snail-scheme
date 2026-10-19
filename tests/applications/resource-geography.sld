;; Scalar probes execute the real seeded geography. Counts exclude the opening
;; rectangle and sealed nest cells; they compare ordinary mine opportunities.
(define-library (tests resource-geography)
  (export answer)
  (import
   (scheme base)
   (siegework terrain)
   (only (lofi core) ann -> I32))
  (begin
    (define (opening? seed x y)
      (within? x y (spawn-x seed) (spawn-y seed) 20))
    (define (near-nest? seed x y radius)
      (or (within? x y (front-x seed 0) (front-y seed 0) radius)
          (within? x y (front-x seed 1) (front-y seed 1) radius)
          (within? x y (front-x seed 2) (front-y seed 2) radius)))
    (define (sample-cell? seed x y ring)
      (and (ground? seed x y) (not (opening? seed x y)) (not (nest-site? seed x y))
           (cond ((= ring 0) (near-nest? seed x y 10))
                 ((= ring 1) (and (near-nest? seed x y 20) (not (near-nest? seed x y 10))))
                 (else (not (near-nest? seed x y 20))))))
    (define (count-cells seed ring deposits)
      (let loop ((cell 0) (total 0))
        (if (= cell (* map-width map-height)) total
            (let ((x (index-x cell)) (y (index-y cell)))
              (loop (+ cell 1)
                    (+ total (if (and (sample-cell? seed x y ring)
                                      (or (not deposits) (> (deposit-rate seed x y) 0))) 1 0)))))))
    (define (fingerprint seed)
      (let loop ((cell 0) (total 0))
        (if (= cell (* map-width map-height)) total
            (let* ((x (index-x cell)) (y (index-y cell))
                   (kind (if (ground? seed x y) 1 (if (water? seed x y) 2 0)))
                   (value (+ kind (* 10 (deposit-rate seed x y)))))
              (loop (+ cell 1) (remainder (+ (* total 31) value) 65521))))))
    (define (bonus-count seed)
      (let loop ((candidate 0) (total 0))
        (if (= candidate 24) total
            (loop (+ candidate 1) (+ total (if (front-deposit? seed (quotient candidate 8) (remainder candidate 8)) 1 0))))))
    (define answer
      (ann (lambda (seed query)
             (cond ((= query 0) (fingerprint seed))
                   ((<= query 6) (count-cells seed (quotient (- query 1) 2) (= (remainder query 2) 0)))
                   (else (bonus-count seed))))
           (-> I32 I32 I32)))))
