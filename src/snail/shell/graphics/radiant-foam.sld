;; A bounded Radiant Foam reference. A site owns the part of the unit
;; cube [-1, 1]^3 closer to it than to any other site. A ray walks these cells in order. Their
;; bisectors also bound the polygons separating dense cells from sparse ones.
(define-library (snail shell graphics radiant-foam)
  (export
   Vec3d vec3d v+ v- v* dot
   Site site Foam make-foam
   Ray ray Sample render-ray fit-step density-faces)
  (import
   (snail core base)
   (only (snail shell math) exp)
   (snail shell wire))
  (begin

    ;; ---- Sites and bisectors ----

    (record Vec3d
      ((x F64)
       (y F64)
       (z F64))
      (deriving Serialize Deserialize))

    (define (vec3d (x F64) (y F64) (z F64)) (→ Vec3d) (new Vec3d (x x) (y y) (z z)))
    (define black (→ Vec3d) (vec3d 0.0 0.0 0.0))

    (define (v+ (a Vec3d) (b Vec3d)) (→ Vec3d)
      (vec3d (+ (● a x) (● b x)) (+ (● a y) (● b y)) (+ (● a z) (● b z))))

    (define (v- (a Vec3d) (b Vec3d)) (→ Vec3d)
      (vec3d (- (● a x) (● b x)) (- (● a y) (● b y)) (- (● a z) (● b z))))

    (define (v* (a Vec3d) (s F64)) (→ Vec3d)
      (vec3d (* (● a x) s) (* (● a y) s) (* (● a z) s)))

    (define (dot (a Vec3d) (b Vec3d)) (→ F64)
      (+ (* (● a x) (● b x)) (+ (* (● a y) (● b y)) (* (● a z) (● b z)))))

    (define (cross (a Vec3d) (b Vec3d)) (→ Vec3d)
      (vec3d (- (* (● a y) (● b z)) (* (● a z) (● b y)))
             (- (* (● a z) (● b x)) (* (● a x) (● b z)))
             (- (* (● a x) (● b y)) (* (● a y) (● b x)))))

    (define (unit-vector (v Vec3d)) (→ Vec3d)
      (let ((length (sqrt (dot v v))))
        (if (> length 0.0) (v* v (/ 1.0 length)) (panic "a direction needs a nonzero length"))))

    (define (in-range? (v Vec3d) (lo F64) (hi F64)) (→ Bool)
      (and (<= lo (● v x)) (<= (● v x) hi)
           (<= lo (● v y)) (<= (● v y) hi)
           (<= lo (● v z)) (<= (● v z) hi)))

    (define (clamp-vector (v Vec3d) (low F64) (high F64)) (→ Vec3d)
      (let ((bound (lambda (x) (min high (max low x)))))
        (vec3d (bound (● v x)) (bound (● v y)) (bound (● v z)))))

    (record Site
      ((position Vec3d)
       (density F64)
       (rgb Vec3d))
      (deriving Serialize Deserialize))

    (define (site (position Vec3d) (density F64) (rgb Vec3d)) (→ Site)
      (new Site (position position) (density density) (rgb rgb)))

    (type Foam (Array Site))

    (define infinity (→ F64) (bits->f64 9218868437227405312))

    (define (same-position? (a Site) (b Site)) (→ Bool)
      (let ((p (● a position)) (q (● b position)))
        (and (= (● p x) (● q x)) (= (● p y) (● q y)) (= (● p z) (● q z)))))

    (define (bounded-site (s Site)) (→ Site)
      (if (and (in-range? (● s position) -1.0 1.0) (in-range? (● s rgb) 0.0 1.0)
               (>= (● s density) 0.0) (< (● s density) infinity))
          s
          (panic
           "foam needs sites in the unit cube, finite nonnegative density, and RGB in [0,1]")))

    ;; Exact coincidences have one owner, the first site at that position.
    (define (make-foam (sites (List Site))) (→ Foam)
      (list->array (delete-duplicates same-position? (map bounded-site sites))))

    ;; The inside of a clipping plane satisfies normal · x <= offset.
    (record Plane
      ((normal Vec3d)
       (offset F64)))

    (define (bisector (p Vec3d) (q Vec3d)) (→ Plane)
      (let ((n (v- q p)))
        (new Plane (normal n) (offset (* 0.5 (dot n (v+ p q)))))))

    (define box (→ (List Plane))
      (map (lambda (n) (new Plane (normal n) (offset 1.0)))
           (list (vec3d 1.0 0.0 0.0) (vec3d -1.0 0.0 0.0)
                 (vec3d 0.0 1.0 0.0) (vec3d 0.0 -1.0 0.0)
                 (vec3d 0.0 0.0 1.0) (vec3d 0.0 0.0 -1.0))))

    ;; ---- Ray intervals ----

    (record Ray
      ((origin Vec3d)
       (direction Vec3d)))

    ;; A unit direction makes a parameter difference a physical distance.
    (define (ray (origin Vec3d) (direction Vec3d)) (→ Ray)
      (new Ray (origin origin) (direction (unit-vector direction))))

    (record Interval
      ((near F64)
       (far F64)))

    (define (clip-ray (r Ray) (planes (List Plane)) (near F64) (far F64))
      (→ (Option Interval))
      (if (>= near far) (None)
          (match planes
            ((Nil) (Some (new Interval (near near) (far far))))
            ((Cons plane rest)
             (let ((speed (dot (● plane normal) (● r direction)))
                   (room (- (● plane offset) (dot (● plane normal) (● r origin)))))
               (cond ((> speed 0.0) (clip-ray r rest near (min far (/ room speed))))
                     ((< speed 0.0) (clip-ray r rest (max near (/ room speed)) far))
                     ((< room 0.0) (None))
                     (else (clip-ray r rest near far))))))))

    ;; At distance t from box entry, squared distance to a site is
    ;; squared - 2*t*along + t². All sites share the last term. The cell
    ;; containing the ray is the lowest line, and a crossing of two
    ;; lines is their sites' bisector. Distances are relative to entry.
    (record ProjectedSite
      ((id I64)
       (site Site)
       (squared F64)
       (along F64)))

    (define (project-sites (foam Foam) (entry Vec3d) (dir Vec3d)) (→ (Array ProjectedSite))
      (array-generate (array-length foam)
                      (lambda (i)
                        (let* ((s (array-ref foam i)) (offset (v- (● s position) entry)))
                          (new ProjectedSite (id i) (site s)
                               (squared (dot offset offset)) (along (dot offset dir)))))))

    ;; A tie at entry goes to the nearer site just ahead. A ray lying
    ;; along a shared face keeps the lower index for the entire tie.
    (define (first-cell (sites (Array ProjectedSite))) (→ ProjectedSite)
      (array-fold (lambda (a b)
                    (if (or (< (● b squared) (● a squared))
                            (and (= (● b squared) (● a squared)) (> (● b along) (● a along))))
                        b a))
                  (array-ref sites 0) sites))

    (record Crossing
      ((distance F64)
       (next ProjectedSite)))

    ;; Only a site farther along the ray can take over. Considering all
    ;; sites includes every possible neighbor. The earliest crossing ends
    ;; the current cell. Along strictly increases even through a zero-length tie.
    (define (next-crossing (sites (Array ProjectedSite)) (here ProjectedSite) (end F64))
      (→ Crossing)
      (array-fold (lambda (best s)
                    (let ((speed (- (● s along) (● here along))))
                      (if (<= speed 0.0) best
                          (let ((t (/ (- (● s squared) (● here squared)) (* 2.0 speed))))
                            (if (< t (● best distance))
                                (new Crossing (distance t) (next s))
                                best)))))
                  (new Crossing (distance end) (next here)) sites))

    (record Segment
      ((cell ProjectedSite)
       (length F64)
       (exit Vec3d)
       (transmission F64)))

    (define (walk (sites (Array ProjectedSite)) (entry Vec3d) (dir Vec3d) (end F64))
      (→ (List Segment))
      (let loop ((cell (first-cell sites)) (near 0.0) (hits (Nil)))
        (let* ((crossing (next-crossing sites cell end))
               (far (max near (● crossing distance))) (length (- far near))
               (seen (if (= length 0.0) hits
                         (Cons
                          (new Segment (cell cell) (length length) (exit (v+ entry (v* dir far)))
                               (transmission (exp (negate (* length (● cell site density))))))
                          hits))))
          (if (>= far end) (reverse seen) (loop (● crossing next) far seen)))))

    (define (ray-segments (foam Foam) (r Ray)) (→ (List Segment))
      (match (clip-ray r box 0.0 infinity)
        ((None) (Nil))
        ((Some span)
         (let* ((dir (● r direction)) (entry (v+ (● r origin) (v* dir (● span near)))))
           (if (= (array-length foam) 0) (Nil)
               (walk (project-sites foam entry dir) entry dir (- (● span far) (● span near))))))))

    (define (over (s Segment) (behind Vec3d)) (→ Vec3d)
      (let ((q (● s transmission)))
        (v+ (v* (● s cell site rgb) (- 1.0 q)) (v* behind q))))

    (define (render-ray (foam Foam) (r Ray)) (→ Vec3d)
      (fold-right over black (ray-segments foam r)))

    ;; ---- Photometric fitting ----

    (record Sample
      ((ray Ray)
       (rgb Vec3d)))

    ;; The batch owns one accumulator per site. All its rays see the same foam.
    (record Gradient
      ((position Vec3d)
       (density F64)
       (rgb Vec3d)))

    ;; Differentiating the bisector at x = origin + t direction gives
    ;; dt/dp = (x-p)/dot(direction,q-p) and dt/dq = (q-x)/dot(direction,q-p).
    ;; A crossing adds distance to the front cell and takes it from the back.
    (define (move-face! (grad (Array Gradient)) (hit Vec3d)
                        (front ProjectedSite) (back ProjectedSite) (dt F64))
      (→ Unit)
      (let ((k (/ dt (- (● back along) (● front along))))
            (a (array-ref grad (● front id))) (b (array-ref grad (● back id))))
        (set! (● a position) (v+ (● a position) (v* (v- hit (● front site position)) k)))
        (set! (● b position) (v+ (● b position) (v* (v- (● back site position) hit) k)))))

    ;; Return the composited suffix and the loss derivative with respect
    ;; to its first segment's length. The incoming RGB adjoint already
    ;; includes transmittance through every preceding segment.
    (define (backward! (grad (Array Gradient)) (hits (List Segment)) (adjoint Vec3d))
      (→ (Pair Vec3d F64))
      (match hits
        ((Nil) (new Pair (first black) (second 0.0)))
        ((Cons s rest)
         (let* ((q (● s transmission)) (cell (● s cell))
                (tail (backward! grad rest (v* adjoint q)))
                (depth (* q (dot adjoint (v- (● cell site rgb) (● tail first)))))
                (length-change (* depth (● cell site density)))
                (g (array-ref grad (● cell id))))
           (set! (● g rgb) (v+ (● g rgb) (v* adjoint (- 1.0 q))))
           (set! (● g density)
                 (+ (● g density) (* depth (● s length))))
           (match rest
             ((Cons next _) (move-face! grad (● s exit) cell (● next cell)
                                        (- length-change (● tail second))))
             ((Nil) (unit)))
           (new Pair (first (over s (● tail first))) (second length-change))))))

    (define (learn-ray! (foam Foam) (grad (Array Gradient)) (sample Sample)) (→ Unit)
      (let* ((r (● sample ray)) (hits (ray-segments foam r))
             (error (v- (fold-right over black hits) (● sample rgb))))
        (backward! grad hits (v* error (/ 2.0 3.0)))
        (unit)))

    ;; Near a grazing crossing dt/dp can be very large. Limit a batch's
    ;; coordinate step to one percent of the box width before projecting
    ;; the new position into the box. Color and extinction use their own bounds.
    (define (descend (s Site) (g Gradient) (step F64)) (→ Site)
      (let ((move (clamp-vector (v* (● g position) step) -0.02 0.02)))
        (site (clamp-vector (v- (● s position) move) -1.0 1.0)
              (max 0.0 (- (● s density) (* (● g density) step)))
              (clamp-vector (v- (● s rgb) (v* (● g rgb) step)) 0.0 1.0))))

    ;; One projected gradient step on mean squared RGB error. The next ray
    ;; sees the boundaries implied by the new positions.
    (define (fit-step (foam Foam) (samples (List Sample)) (rate F64)) (→ Foam)
      (if (null? samples) foam
          (let ((grad (array-generate (array-length foam)
                                      (lambda (_)
                                        (new Gradient (position black) (density 0.0) (rgb black)))))
                (step (/ rate (i64->f64 (length samples)))))
            (for-each (lambda (s) (learn-ray! foam grad s)) samples)
            (make-foam (map-indexed (lambda (i s) (descend s (array-ref grad i) step))
                                    (array->list foam))))))

    ;; ---- Density interfaces ----

    ;; Clip a convex polygon, preserving its winding. A vertex already
    ;; on the plane is emitted once. Only a strict crossing adds a vertex.
    (define (clip-polygon (polygon (List Vec3d)) (plane Plane)) (→ (List Vec3d))
      (let ((distance (lambda (p) (- (dot (● plane normal) p) (● plane offset)))))
        (match (last polygon)
          ((None) (Nil))
          ((Some last-point)
           (let loop ((rest polygon) (a last-point) (da (distance last-point)) (result (Nil)))
             (match rest
               ((Nil) (reverse result))
               ((Cons b tail)
                (let* ((db (distance b))
                       (cut (if (< (* da db) 0.0)
                                (Cons (v+ a (v* (v- b a) (/ da (- da db)))) result) result)))
                  (loop tail b db (if (<= db 0.0) (Cons b cut) cut))))))))))

    ;; A square on the bisector with outward winding. Four units from its
    ;; midpoint in either tangent direction covers the cube's full diagonal.
    (define (bisector-square (p Vec3d) (q Vec3d)) (→ (List Vec3d))
      (let* ((mid (v* (v+ p q) 0.5)) (n (unit-vector (v- q p)))
             (axis (if (< (abs (● n x)) 0.8) (vec3d 1.0 0.0 0.0) (vec3d 0.0 1.0 0.0)))
             (u (v* (unit-vector (cross axis n)) 4.0)) (v (cross n u)))
        (list (v- (v- mid u) v) (v- (v+ mid u) v) (v+ (v+ mid u) v) (v+ (v- mid u) v))))

    ;; Coplanar clipping planes can leave an edge or a point. Keep only
    ;; distinct corners at which the convex face turns. The tolerances
    ;; are in the normalized cube, well below the OBJ's vertex precision.
    (define (face-corners (polygon (List Vec3d))) (→ (List Vec3d))
      (let ((same? (lambda (p q) (let ((d (v- p q))) (< (dot d d) 1e-22)))))
        (match (delete-duplicates same? polygon)
          ((Cons a (Cons b rest))
           (let loop ((p a) (q b) (tail (append rest (list a b))) (corners (Nil)))
             (match tail
               ((Nil) (reverse corners))
               ((Cons r more)
                (let ((n (cross (v- q p) (v- r q))))
                  (loop q r more (if (> (dot n n) 1e-26) (Cons q corners) corners)))))))
          (_ (Nil)))))

    (define (face-between (sites (List Site)) (a Site) (b Site)) (→ (List Vec3d))
      (let* ((p (● a position)) (square (bisector-square p (● b position)))
             (others
              (filter (lambda (s) (not (or (same-position? s a) (same-position? s b)))) sites)))
        (face-corners (fold-left (lambda (face s) (clip-polygon face (bisector p (● s position))))
                                 (fold-left clip-polygon square box) others))))

    ;; Each dense/sparse face once, facing the sparse site. The box clips
    ;; these interfaces. Only changes in material supply faces.
    (define (density-faces (foam Foam) (threshold F64)) (→ (List (List Vec3d)))
      (let* ((sites (array->list foam))
             (dense? (lambda (c) (>= (● c density) threshold)))
             (sparse (filter (lambda (c) (not (dense? c))) sites)))
        (filter (lambda (face) (>= (length face) 3))
                (concatenate
                 (map (lambda (c) (map (lambda (other) (face-between sites c other)) sparse))
                      (filter dense? sites))))))

    ))
