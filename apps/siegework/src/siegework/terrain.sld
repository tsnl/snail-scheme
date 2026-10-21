;; The seeded land: grass, rock and water on an 80 by 80 map, the hub's
;; place, three nest fronts and the crystal sites. Every value is computed
;; from the seed with bounded integer products, so a seed alone reproduces
;; the land and no random state is threaded through generation.
;;
;; The geography is the original Siegework's: a fixed home neighborhood
;; translated to the hub (a ridge east of it, a northern wall and a southern
;; rock bed, each with crossings), one bending lake or mountain ellipse per
;; 32-cell region, and three nest fronts 20 to 25 cells out at turns of
;; 120 degrees, each in a six-cell clearing.
(define-library (siegework terrain)
  (export
   Ground
   Grass
   Rock
   Water
   Site
   Site-cell
   Site-rate
   Land
   Land-seed
   Land-hub
   Land-ground
   Land-sites
   Land-fronts
   new-land
   land-seed
   ground-at
   nest-rate
   reserve-per-rate)
  (import
   (lofi base)
   (lofi wire)
   (siegework grid))
  (begin

    ;; ---- Land ----

    (enum Ground
      (Grass)
      (Rock)
      (Water)
      (deriving Serialize Deserialize))

    ;; A crystal site yields `rate` energy per second for each extractor
    ;; level until its reserve of `reserve-per-rate` times `rate` runs out.
    (struct Site
      ((cell Cell)
       (rate I64))
      (deriving Serialize Deserialize))

    (struct Land
      ((seed I64)
       (hub Cell)
       (ground (Vector Ground))
       (sites (List Site))
       (fronts (List Cell)))
      (deriving Serialize Deserialize))

    (: reserve-per-rate I64)
    (define reserve-per-rate 300)

    ;; The crystal beneath each nest, exposed when the nest is destroyed.
    (: nest-rate I64)
    (define nest-rate 8)

    (: ground-at (-> Land Cell Ground))
    (define (ground-at land cell)
      (vector-ref (Land-ground land) (cell-index cell)))

    ;; Seeds are 1 to 65535; any integer maps into that range.
    (: land-seed (-> I64 I64))
    (define (land-seed seed)
      (+ 1 (modulo seed 65535)))

    (: new-land (-> I64 Land))
    (define (new-land seed)
      (Land seed (Cell (spawn-x seed) (spawn-y seed))
            (vector-generate (* map-size map-size) (lambda (index) (ground-of seed (index-cell index))))
            ;; A cell holds at most one site; the first listed keeps it.
            (delete-duplicates (lambda (a b) (cell=? (Site-cell a) (Site-cell b)))
                               (append (home-sites seed) (append (regional-sites seed) (front-sites seed))))
            (map (lambda (front) (Cell (front-x seed front) (front-y seed front))) (list 0 1 2))))

    ;; ---- Seeded offsets ----

    ;; Seeds and the keys derived from them stay below 2^18 and strides below
    ;; 2^10, so the product never overflows.
    (: map-offset (-> I64 I64 I64 I64))
    (define (map-offset seed stride count)
      (remainder (remainder (* seed stride) 65521) count))

    (: inside? (-> I64 I64 Bool))
    (define (inside? x y)
      (in-bounds? (Cell x y)))

    (: within-xy? (-> I64 I64 I64 I64 I64 Bool))
    (define (within-xy? x y a b radius)
      (within? (Cell x y) (Cell a b) radius))

    ;; ---- The hub and the nest fronts ----

    ;; The hub sits within four cells of the map's center. Rejection keeps
    ;; that a disc; each attempt derives a new seed, with no random state.
    (: spawn-offset (-> I64 I64 Bool I64))
    (define (spawn-offset seed attempt horizontal)
      (let ((x (- (map-offset seed 73 9) 4)) (y (- (map-offset seed 151 9) 4)))
        (cond ((<= (+ (* x x) (* y y)) 16) (if horizontal x y))
              ((= attempt 23) 0)
              (else (spawn-offset (remainder (+ (* seed 25173) 13849) 65521) (+ attempt 1) horizontal)))))

    (: spawn-x (-> I64 I64))
    (define (spawn-x seed)
      (+ (quotient map-size 2) (spawn-offset seed 0 #t)))

    (: spawn-y (-> I64 I64))
    (define (spawn-y seed)
      (+ (quotient map-size 2) (spawn-offset seed 0 #f)))

    ;; The first front lies 20 to 25 cells out along a seeded axis.
    (: nest-offset (-> I64 Bool I64))
    (define (nest-offset seed horizontal)
      (let ((direction (map-offset seed 67 4)) (major (+ 20 (map-offset seed 173 6))) (minor (- (map-offset seed 227 9) 4)))
        (if (= (remainder direction 2) (if horizontal 0 1))
            (if (< direction 2) major (- 0 major))
            minor)))

    ;; The other two fronts are integer rotations of the first by 120 degrees.
    (: front-offset (-> I64 I64 Bool I64))
    (define (front-offset seed front horizontal)
      (let ((x (nest-offset seed #t)) (y (nest-offset seed #f)) (turn (if (= front 1) 866 -866)))
        (cond ((= front 0) (if horizontal x y))
              (horizontal (quotient (- (* -500 x) (* turn y)) 1000))
              (else (quotient (+ (* turn x) (* -500 y)) 1000)))))

    (: front-x (-> I64 I64 I64))
    (define (front-x seed front)
      (+ (spawn-x seed) (front-offset seed front #t)))

    (: front-y (-> I64 I64 I64))
    (define (front-y seed front)
      (+ (spawn-y seed) (front-offset seed front #f)))

    (: nest-site? (-> I64 I64 I64 Bool))
    (define (nest-site? seed x y)
      (any? (lambda (front) (and (= x (front-x seed front)) (= y (front-y seed front)))) (list 0 1 2)))

    (: nest-clearing? (-> I64 I64 I64 Bool))
    (define (nest-clearing? seed x y)
      (any? (lambda (front) (within-xy? x y (front-x seed front) (front-y seed front) 6)) (list 0 1 2)))

    ;; ---- The home neighborhood ----

    ;; Home coordinates place the hub at (8, 22) of a 48 by 36 neighborhood
    ;; whose features keep their shape on every map.
    (: home-x (-> I64 I64 I64))
    (define (home-x seed x)
      (+ (- x (spawn-x seed)) 8))

    (: home-y (-> I64 I64 I64))
    (define (home-y seed y)
      (+ (- y (spawn-y seed)) 22))

    (: home-cell? (-> I64 I64 Bool))
    (define (home-cell? x y)
      (and (>= x 0) (< x 48) (>= y 0) (< y 36)))

    ;; The ridge stays east of the hub. Its crossing is at least three cells
    ;; tall, and its southern end leaves a second way around.
    (: ridge? (-> I64 I64 I64 Bool))
    (define (ridge? seed x y)
      (let ((left (if (= seed 1) 23 (+ 22 (map-offset seed 31 5))))
            (opening (if (= seed 1) 16 (+ 15 (map-offset seed 43 7))))
            (height (if (= seed 1) 4 3)))
        (and (>= x left) (<= x (+ left 1)) (< y 31) (or (< y opening) (>= y (+ opening height))))))

    ;; The northern crystal is above this wall; its gap and the open strip at
    ;; x = 19 to 21 both connect it to the hub.
    (: northern-wall? (-> I64 I64 I64 Bool))
    (define (northern-wall? seed x y)
      (let ((row (if (= seed 1) 10 (+ 9 (map-offset seed 59 4))))
            (opening (if (= seed 1) 10 (+ 8 (map-offset seed 83 7))))
            (width (if (= seed 1) 4 3)))
        (and (= y row) (< x 19) (or (< x opening) (>= x (+ opening width))))))

    ;; An isolated rock bed below the eastern crystal, with room on every side.
    (: southern-rock? (-> I64 I64 I64 Bool))
    (define (southern-rock? seed x y)
      (let ((left (if (= seed 1) 32 (+ 31 (map-offset seed 107 7)))) (top (if (= seed 1) 25 (+ 24 (map-offset seed 127 5)))))
        (and (>= x left) (<= x (+ left 6)) (>= y top) (<= y (+ top 3)))))

    (: home-ground? (-> I64 I64 I64 Bool))
    (define (home-ground? seed x y)
      (not (or (ridge? seed x y) (northern-wall? seed x y) (southern-rock? seed x y))))

    ;; ---- Regions ----

    ;; Each 32-cell region holds one bending ellipse of water or mountain, or
    ;; open land. Its outer rows and columns stay clear, joining neighboring
    ;; regions into walking corridors.
    (: region-value (-> I64 I64 I64 I64 I64 I64))
    (define (region-value seed x y stride count)
      (map-offset (+ seed (+ (* (quotient x 32) 97) (* (quotient y 32) 193))) stride count))

    (: triangle (-> I64 I64))
    (define (triangle value)
      (- (abs (- (remainder value 24) 12)) 6))

    (: region-shape? (-> I64 I64 I64 I64 I64 Bool))
    (define (region-shape? seed x y width height)
      (let* ((v (- (remainder y 32) 16))
             (bend (quotient (triangle (+ (remainder y 32) (map-offset seed 41 24))) 3))
             (u (- (remainder x 32) (+ 16 bend)))
             (w (+ width (region-value seed x y 109 3))))
        (<= (+ (* (* u u) (* height height)) (* (* v v) (* w w))) (* (* w w) (* height height)))))

    (: region-water? (-> I64 I64 I64 Bool))
    (define (region-water? seed x y)
      (and (= (region-value seed x y 137 5) 0) (region-shape? seed x y 5 9)))

    (: region-mountain? (-> I64 I64 I64 Bool))
    (define (region-mountain? seed x y)
      (let ((kind (region-value seed x y 137 5)))
        (and (> kind 0) (< kind 4) (region-shape? seed x y 3 11))))

    ;; ---- Ground ----

    ;; Nest clearings are always grass; the home neighborhood is grass but
    ;; for its rock features; elsewhere each region decides.
    (: ground-of (-> I64 Cell Ground))
    (define (ground-of seed cell)
      (let ((x (Cell-x cell)) (y (Cell-y cell)))
        (cond ((nest-clearing? seed x y) (Grass))
              ((home-cell? (home-x seed x) (home-y seed y)) (if (home-ground? seed (home-x seed x) (home-y seed y)) (Grass) (Rock)))
              ((region-water? seed x y) (Water))
              ((region-mountain? seed x y) (Rock))
              (else (Grass)))))

    (: grass? (-> I64 I64 I64 Bool))
    (define (grass? seed x y)
      (and (inside? x y) (match (ground-of seed (Cell x y)) ((Grass) #t) (_ #f))))

    ;; ---- Crystal sites ----

    ;; A starter beside the hub, a northern one above the wall and a rich
    ;; eastern one past the ridge.
    (: home-sites (-> I64 (List Site)))
    (define (home-sites seed)
      (let ((x (spawn-x seed)) (y (spawn-y seed)))
        (list (Site (Cell (+ x 4) (- y 2)) 2)
              (Site (Cell (+ x (- (map-offset seed 73 5) 2)) (- y 9)) 3)
              (Site (Cell (eastern-x seed) (- y (+ 4 (map-offset seed 239 3)))) 6))))

    (: eastern-x (-> I64 I64))
    (define (eastern-x seed)
      (let ((x (+ (spawn-x seed) 13)) (y (- (spawn-y seed) (+ 4 (map-offset seed 239 3)))))
        (if (nest-site? seed x y) (- x 1) x)))

    ;; One region in four holds a site in its open corner corridor, outside
    ;; the home neighborhood.
    (: regional-sites (-> I64 (List Site)))
    (define (regional-sites seed)
      (let ((regions (quotient (+ map-size 31) 32)))
        (filter-map (lambda (region)
                      (let* ((rx (* 32 (remainder region regions))) (ry (* 32 (quotient region regions)))
                             (x (+ rx (+ 2 (region-value seed rx ry 157 3)))) (y (+ ry (+ 2 (region-value seed rx ry 181 3)))))
                        (if (and (= (region-value seed x y 347 4) 0) (inside? x y) (not (nest-site? seed x y))
                                 (not (home-cell? (home-x seed x) (home-y seed y))))
                            (Some (Site (Cell x y) (+ 2 (region-value seed x y 211 5))))
                            (None))))
                    (iota (* regions regions)))))

    ;; Eight candidates per front: four inner ones 4 to 6 cells out accepted
    ;; with chance 3/16, and four outer ones 8 to 10 out with chance 1/16.
    ;; Following an attack back to its nest leads to richer ground.
    (: front-sites (-> I64 (List Site)))
    (define (front-sites seed)
      (filter-map (lambda (candidate) (front-site seed (quotient candidate 8) (remainder candidate 8))) (iota 24)))

    (: front-site (-> I64 I64 I64 (Option Site)))
    (define (front-site seed front slot)
      (let* ((key (+ seed (+ (* front 997) (* slot 271))))
             (major (+ (if (< slot 4) 4 8) (map-offset key 307 3)))
             (along (if (< (remainder slot 4) 2) major (- 0 major)))
             (across (- (map-offset key 317 5) 2))
             (horizontal (= (remainder slot 2) 0))
             (x (+ (front-x seed front) (if horizontal along across)))
             (y (+ (front-y seed front) (if horizontal across along))))
        (if (and (< (map-offset key 313 16) (if (< slot 4) 3 1)) (grass? seed x y)
                 (not (within-xy? x y (spawn-x seed) (spawn-y seed) 10)) (not (nest-site? seed x y)))
            (Some (Site (Cell x y) 2))
            (None))))

    (: filter-map (All (A B) (-> (-> A (Option B)) (List A) (List B))))
    (define (filter-map f items)
      (fold-right (lambda (item kept) (match (f item) ((Some value) (Cons value kept)) ((None) kept))) (Nil) items))

    ))
