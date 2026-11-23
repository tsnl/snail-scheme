;; Static geometry follows the same building footprints the simulation sweeps.
(define-library (apps last-mile street)
  (export street-items prop-items)
  (import
   (snail core base)
   (snail shell app)
   (snail shell game drawing)
   (snail shell game physics)
   (apps last-mile district)
   (apps last-mile game))
  (begin
    (define curb (→ I32) (rgb 173 163 146))
    (define tar (→ I32) (rgb 79 80 81))
    (define glass (→ I32) (rgb 66 90 101))
    (define cream (→ I32) (rgb 230 214 179))
    (define red (→ I32) (rgb 202 67 45))

    (define (facade (b Building)) (→ (List Item))
      (let* ((i (● b style)) (w (● b width)) (h (● b height)) (d (● b depth))
             (brick
              (list-ref (list (rgb 172 103 78) (rgb 191 166 121) (rgb 149 107 95) (rgb 163 158 144))
                        (modulo i 4)))
             (awning (if (= (modulo i 2) 0) (rgb 53 114 102) (rgb 169 77 56))))
        (place-parts
         (append (list (piece (Box) curb 0.0 0.0 0.0 (+ w 2.4) 0.18 (+ d 2.8) 0.0)
                       (piece (Box) brick 0.0 0.18 0.0 w h d 0.0)
                       (piece (Box) cream 0.0 h 0.0 (+ w 0.4) 0.36 (+ d 0.4) 0.0)
                       (piece (Box) tar 1.0 (+ h 0.36) -1.0 2.8 0.75 2.3 0.0)
                       (piece (Box) glass 0.0 0.2 (* d 0.5) (* w 0.64) 2.1 0.12 0.0)
                       (piece (Box) awning 0.0 2.35 (* d 0.5) (* w 0.76) 0.3 1.8 0.0))
                 (concatenate (map (lambda (floor)
                                     (let ((y (+ 3.1 (* 3.0 (i64->f64 floor)))))
                                       (list
                                        (piece (Box) glass 0.0 y 0.0 (* w 0.84) 1.1 (+ d 0.1) 0.0)
                                        (piece (Box) glass 0.0 y 0.0 (+ w 0.1) 1.1 (* d 0.74) 0.0)
                                        (piece (Box)
                                               cream
                                               0.0
                                               (- y 0.18)
                                               0.0
                                               (+ w 0.18)
                                               0.14
                                               (+ d 0.18)
                                               0.0))))
                                   (iota (f64->i64 (/ (- h 1.0) 3.0))))))
         (● b center) 0.0 0.0)))

    (define (markings) (→ (List Item))
      (append (concatenate (map (lambda (i)
                                  (let ((z (+ -50.0 (* 5.0 (i64->f64 i)))))
                                    (list
                                     (piece (Tile) (rgb 226 185 87) 0.0 0.025 z 0.13 1.0 2.65 0.0)
                                     (piece (Tile) cream 20.0 0.025 z 0.12 1.0 2.65 0.0))))
                                (iota 19)))
              (concatenate
               (map (lambda (z) (map (lambda (i) (piece (Tile) cream (+ -2.5 (i64->f64 i))
                                                        0.035 z 0.58 1.0 1.25 0.0)) (iota 6)))
                    (list 13.5 -3.3 -27.0)))))

    (define (trees) (→ (List Item))
      (concatenate (map (lambda (p)
                          (let ((z (● p z)) (x (● p x)))
                            (list (piece (Prism) (rgb 103 81 64) x 0.0 z 0.28 2.8 0.3 0.0)
                                  (piece (Sphere) (rgb 85 124 78) x 2.2 z 2.9 2.3 2.4 0.0))))
                        tree-sites)))

    (define (cutting-room-items) (→ (List Item))
      (place-parts (list (piece (Box) (rgb 42 87 87) 0.0 0.0 0.0 2.5 1.08 0.85 0.0)
                         (piece (Box) cream 0.0 1.08 0.0 2.85 0.12 1.05 0.0)
                         (piece (Box) red 0.85 1.2 0.0 0.17 1.8 0.14 0.0)
                         (piece (Box) cream 0.3 2.4 0.0 1.25 0.55 0.1 0.0)) cutting-room 0.0 0.0))

    (define (street-items) (→ (List Item))
      (concatenate (list (list (piece (Box) tar 0.0 -0.4 -4.0 140.0 0.4 145.0 0.0))
                         (markings)
                         (trees)
                         (cutting-room-items)
                         (concatenate (map facade buildings)))))

    ;; The plate and gate drop together. They retain their mesh slots across takes.
    (define (prop-items (w World)) (→ (List Item))
      (let ((y (match (● w mission) ((Pickup) 0.0) ((Action) 0.0) (_ -3.0))))
        (list (piece (Box) cream 0.0 (+ y 0.78) -15.0 8.8 0.27 0.16 0.0)
              (piece (Box) red 0.0 (+ y 0.87) -14.9 8.7 0.09 0.06 0.0)
              (piece (Box) tar (● target x) y (● target z) 0.13 1.5 0.13 0.0)
              (piece (Box) red (● target x) (+ y 0.97) (● target z) 1.65 1.3 0.15 0.0)
              (piece (Box) cream (● target x) (+ y 1.25) (+ (● target z) 0.09) 0.84 0.74 0.03 0.0)
              (piece (Box) red (● target x) (+ y 1.44) (+ (● target z) 0.12) 0.4 0.36 0.02 0.0))))))