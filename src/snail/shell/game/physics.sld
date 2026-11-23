;; Planar kinematics, in metres and seconds. Bodies slide along solid,
;; axis-aligned footprints. Sweep the whole displacement to first contact so even
;; a fast vehicle cannot skip a thin wall between simulation ticks.
(define-library (snail shell game physics)
  (export XZ xz distance heading-to forward offset Footprint footprint clear?
          Body body travel walk clear-path? trace-distance)
  (import
   (snail core base)
   (snail shell math)
   (snail shell wire))
  (begin

    (record XZ
      ((x F64)
       (z F64))
      (deriving Serialize Deserialize))

    (define (xz (x F64) (z F64)) (→ XZ) (new XZ (x x) (z z)))

    (define (distance (a XZ) (b XZ)) (→ F64)
      (let ((x (- (● a x) (● b x))) (z (- (● a z) (● b z))))
        (sqrt (+ (* x x) (* z z)))))

    ;; Heading zero faces north (-z), positive angles turn toward +x.
    (define (heading-to (a XZ) (b XZ)) (→ F64)
      (atan2 (- (● b x) (● a x)) (- (● a z) (● b z))))

    (define (forward (angle F64)) (→ XZ) (xz (sin angle) (negate (cos angle))))

    (define (offset (p XZ) (v XZ) (amount F64)) (→ XZ)
      (xz (+ (● p x) (* amount (● v x))) (+ (● p z) (* amount (● v z)))))

    (record Footprint
      ((west F64)
       (east F64)
       (north F64)
       (south F64)))

    (define (footprint (x F64) (z F64) (width F64) (depth F64)) (→ Footprint)
      (new Footprint (west (- x (* 0.5 width))) (east (+ x (* 0.5 width)))
           (north (- z (* 0.5 depth))) (south (+ z (* 0.5 depth)))))

    (define (overlaps? (at F64) (radius F64) (low F64) (high F64)) (→ Bool)
      (and (> (+ at radius) low) (< (- at radius) high)))

    (define (clear? (p XZ) (radius F64) (walls (List Footprint))) (→ Bool)
      (not (any? (lambda (w) (and (overlaps? (● p x) radius (● w west) (● w east))
                                  (overlaps? (● p z) radius (● w north) (● w south)))) walls)))

    ;; Time is a fraction of this displacement. A parallel path touches
    ;; a face freely and only intersects the open space between the faces.
    (define (interval (at F64) (delta F64) (low F64) (high F64)) (→ (Option (Pair F64 F64)))
      (if (< (abs delta) 0.000000001)
          (if (and (> at (+ low 0.000000001)) (< at (- high 0.000000001)))
              (Some (new Pair (first -1e30) (second 1e30))) (None))
          (let ((a (/ (- low at) delta)) (b (/ (- high at) delta)))
            (Some (new Pair (first (min a b)) (second (max a b)))))))

    (record Contact
      ((time F64)
       (block-x Bool)
       (block-z Bool)))

    (define free (→ Contact) (new Contact (time 1.0) (block-x #f) (block-z #f)))

    (define (contact (p XZ) (v XZ) (radius F64) (wall Footprint)) (→ Contact)
      (let ((x (interval (● p x) (● v x) (- (● wall west) radius) (+ (● wall east) radius)))
            (z (interval (● p z) (● v z) (- (● wall north) radius) (+ (● wall south) radius))))
        (match (new Pair (first x) (second z))
          ((Pair (Some a) (Some b))
           (let ((entry (max (● a first) (● b first))) (exit (min (● a second) (● b second))))
             (if (and (>= entry -0.000000001) (< entry 1.0) (> exit (max 0.0 entry)))
                 (new Contact (time (max 0.0 entry)) (block-x (>= (● a first) (● b first)))
                      (block-z (>= (● b first) (● a first)))) free)))
          (_ free))))

    (define (first-contact (p XZ) (delta XZ) (r F64) (walls (List Footprint))) (→ Contact)
      (fold-left (lambda (nearest w)
                   (let ((hit (contact p delta r w)))
                     (if (< (● hit time) (● nearest time)) hit nearest)))
                 free walls))

    (define (clear-path? (from XZ) (to XZ) (radius F64) (walls (List Footprint))) (→ Bool)
      (and (clear? from radius walls) (clear? to radius walls)
           (= (● (first-contact from
                                (xz (- (● to x) (● from x)) (- (● to z) (● from z)))
                                radius
                                walls)
                 time)
              1.0)))

    (record Body
      ((position XZ)
       (velocity XZ)
       (heading F64))
      (deriving Serialize Deserialize))

    (define (body (p XZ) (angle F64)) (→ Body)
      (new Body (position p) (velocity (xz 0.0 0.0)) (heading angle)))

    (define (travel (p XZ) (v XZ) (angle F64) (radius F64) (walls (List Footprint)) (dt F64))
      (→ Body)
      ;; Losing the normal velocity at contact leaves only tangent motion.
      ;; With axis-aligned faces a second contact can stop the other axis.
      (let slide ((at p) (velocity v) (remaining dt) (contacts 0))
        (let* ((hit (first-contact at
                                   (xz (* remaining (● velocity x)) (* remaining (● velocity z)))
                                   radius
                                   walls))
               (t (● hit time)) (end (offset at velocity (* t remaining))))
          (if (= t 1.0) (new Body (position end) (velocity velocity) (heading angle))
              (let ((tangent (xz (if (● hit block-x) 0.0 (● velocity x))
                                 (if (● hit block-z) 0.0 (● velocity z)))))
                (if (= contacts 1) (new Body (position end) (velocity tangent) (heading angle))
                    (slide end tangent (* remaining (- 1.0 t)) (+ contacts 1))))))))

    (define (walk (b Body) (angle F64) (speed F64) (walls (List Footprint)) (dt F64)) (→ Body)
      (travel (● b position) (offset (xz 0.0 0.0) (forward angle) speed) angle 0.36 walls dt))

    ;; Clip a ray to a slab, intersecting the interval from the previous
    ;; axis. A parallel ray either lies in the slab or misses it entirely.
    (define (slab (at F64) (v F64) (low F64) (high F64) (near F64) (far F64))
      (→ (Pair F64 F64))
      (if (< (abs v) 0.0000001)
          (new Pair (first (if (or (< at low) (> at high)) (+ far 1.0) near)) (second far))
          (let ((a (/ (- low at) v)) (b (/ (- high at) v)))
            (new Pair (first (max near (min a b))) (second (min far (max a b)))))))

    (define (trace-distance (p XZ) (direction XZ) (reach F64) (walls (List Footprint))) (→ F64)
      (fold-left (lambda (far w)
                   (let* ((x (slab (● p x) (● direction x) (● w west) (● w east) 0.0 far))
                          (z (slab (● p z)
                                   (● direction z)
                                   (● w north)
                                   (● w south)
                                   (● x first)
                                   (● x second))))
                     (if (<= (● z first) (● z second)) (● z first) far)))
                 reach walls))))
