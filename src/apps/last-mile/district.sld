;; Every building's footprint supplies both the street collider and the
;; facade in the scene. Roads run through the gaps between blocks.
(define-library (apps last-mile district)
  (export Building buildings tree-sites canopies walls gate target cutting-room parking)
  (import
   (snail core base)
   (snail shell game physics))
  (begin
    (record Building
      ((center XZ)
       (width F64)
       (depth F64)
       (height F64)
       (style I64)))

    (define buildings (→ (List Building))
      (concatenate
       (map (lambda (i)
              (map (lambda (j)
                     (let ((n (+ (* i 4) j)))
                       (new Building (center (xz (+ -32.0 (* 21.0 (i64->f64 i)))
                                                 (+ -42.0 (* 24.0 (i64->f64 j)))))
                            (width (if (= (modulo n 3) 0) 14.0 13.0)) (depth 15.0)
                            (height
                             (+ 4.0 (i64->f64 (modulo (* n 7) (if (or (= j 2) (= j 3)) 9 17)))))
                            (style n))))
                   (iota 4)))
            (iota 4))))

    (define tree-sites (→ (List XZ))
      (map (lambda (i) (xz (if (= (remainder i 2) 0) 2.75 -3.55) (+ -34.0 (* 12.0 (i64->f64 i)))))
           (iota 7)))

    (define canopies (→ (List Footprint))
      (map (lambda (p) (footprint (● p x) (● p z) 3.1 2.6)) tree-sites))

    (define walls (→ (List Footprint))
      (append (map (lambda (b) (footprint (● b center x) (● b center z) (● b width) (● b depth)))
                   buildings)
              (append (map (lambda (p) (footprint (● p x) (● p z) 0.3 0.3)) tree-sites)
                      (list (footprint -45.0 -6.0 2.0 100.0) (footprint 44.0 -6.0 2.0 100.0)
                            (footprint 0.0 -55.0 96.0 2.0) (footprint 0.0 43.0 96.0 2.0)))))

    (define parking (→ XZ) (xz 0.0 17.0))
    (define target (→ XZ) (xz 0.0 -13.0))
    (define cutting-room (→ XZ) (xz 20.0 -30.0))
    (define gate (→ Footprint) (footprint 0.0 -15.0 9.0 0.45))
    ))
