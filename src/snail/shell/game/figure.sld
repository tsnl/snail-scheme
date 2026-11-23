;; A figure in a work jacket with paired hips, knees, boots, shoulders and hands.
;; All offsets are local, so the same pose works beside a car or in its seat.
(define-library (snail shell game figure)
  (export figure)
  (import
   (snail core base)
   (snail shell app)
   (snail shell game drawing)
   (snail shell game humanoid))
  (begin
    (define denim (→ I32) (rgb 28 39 54))
    (define skin (→ I32) (rgb 186 137 106))

    (define (leg (p Pose) (side F64) (lift F64)) (→ (List Item))
      (let* ((step (* side (● p step))) (x (* side 0.18))
             (knee (- (* step 0.55) (* 0.34 (● p seat))))
             (boot (- step (* 0.32 (● p seat)))))
        (list (piece (Prism) denim x (+ 0.41 (* lift 0.5)) knee 0.25 0.45 0.28 0.0)
              (piece (Box) (rgb 103 119 132) x (+ 0.15 lift) boot 0.19 0.31 0.22 0.0)
              (piece (Box) denim x lift (- boot 0.06) 0.24 0.2 0.4 0.0))))

    (define (arm (p Pose) (color I32) (side F64) (hip F64)) (→ (List Item))
      (let* ((x (* side 0.37)) (swing (* side (● p step)))
             (reach (max (● p seat) (if (> side 0.0) (● p reach) 0.0))))
        (list (piece (Sphere) color x (+ hip 0.34) 0.0 0.26 0.29 0.3 0.0)
              (piece (Prism) denim x (+ hip 0.09) (* -0.4 reach) 0.2 0.33 0.21 0.0)
              (piece (Box)
                     color
                     x
                     (+ hip (* 0.19 reach))
                     (- swing (* 0.48 reach))
                     0.19
                     0.2
                     0.25
                     0.0))))

    (define (figure (g Gait) (color I32)) (→ (List Item))
      (let* ((p (pose g)) (hip (+ 0.82 (- (● p bob) (* 0.4 (● p seat))))))
        (concatenate (list
                      (list (piece (Prism) color 0.0 hip 0.0 0.68 0.56 0.42 0.0)
                            (piece (Sphere) skin 0.0 (+ hip 0.54) -0.015 0.38 0.40 0.36 0.0)
                            (piece (Sphere) denim 0.0 (+ hip 0.81) 0.0 0.41 0.16 0.38 0.0)
                            (piece (Box) denim 0.0 (+ hip 0.84) -0.19 0.32 0.045 0.21 0.0))
                      (leg p -1.0 (● p left-lift)) (leg p 1.0 (● p right-lift))
                      (arm p color -1.0 hip) (arm p color 1.0 hip)))))))
