;; The seeded land: a biome, and open ground, rock, water and ice on an
;; 80 by 80 map, with the hub's place, three nest fronts and the crystal
;; sites. Every value is computed from the seed by integer hashing whose
;; products stay below 2^62, so a seed alone reproduces the land on both
;; hosts and no random state is threaded through generation.
;;
;; Generation runs in stages, each taking the last one's result:
;;
;; 1. The seed picks the biome, the hub's place within four cells of the
;;    center, and three nest fronts 20 to 25 cells out at turns of 120
;;    degrees, as in the original Siegework.
;; 2. Two smooth noise fields, height and wetness, give each cell its wild
;;    ground in the biome's way.
;; 3. Clearings open the ground around the hub and each front.
;; 4. Passes open the fewest blocked cells between each front and the hub,
;;    so every attack can walk in.
;; 5. Crystal sites go on open ground the hub can wire toward: a starter
;;    four cells out, two richer ones farther, some across the map and
;;    one near most nests.
(define-library (siegework terrain)
  (export
   Biome
   Meadow
   Desert
   Tundra
   Archipelago
   biome-name
   Ground
   Open
   Rock
   Water
   Ice
   Site
   Site-cell
   Site-rate
   Land
   Land-seed
   Land-biome
   Land-hub
   Land-starter
   Land-ground
   Land-mainland
   Land-sites
   Land-fronts
   new-land
   land-seed
   ground-at
   mainland?
   nest-rate
   reserve-per-rate)
  (import
   (snail-core base)
   (siegework grid))
  (begin

    ;; ---- Land ----

    ;; A biome shapes the wild ground and gives it its colors.
    (enum Biome
      (Meadow)
      (Desert)
      (Tundra)
      (Archipelago))

    ;; Open ground is walked and built on. Rock stops walkers, sight and
    ;; wires until it is dug out. Water stops only walkers. Ice is walked
    ;; but cannot be built on.
    (enum Ground
      (Open)
      (Rock)
      (Water)
      (Ice))

    ;; A crystal site yields `rate` energy per second for each extractor
    ;; level until its reserve of `reserve-per-rate` times `rate` runs out.
    (struct Site
      ((cell Cell)
       (rate I64)))

    ;; `starter` is the first crystal, four cells from the hub, and also the
    ;; first site. `mainland` marks the cells joined to the hub without
    ;; crossing water, the only ones enemies, who start at the fronts, can
    ;; ever reach.
    (struct Land
      ((seed I64)
       (biome Biome)
       (hub Cell)
       (starter Cell)
       (ground (Vector Ground))
       (mainland (Vector Bool))
       (sites (List Site))
       (fronts (List Cell))))

    (: reserve-per-rate I64)
    (define reserve-per-rate 300)

    ;; The crystal beneath each nest, exposed when the nest is destroyed.
    (: nest-rate I64)
    (define nest-rate 8)

    (: biome-name (-> Biome String))
    (define (biome-name biome)
      (match biome
        ((Meadow) "Meadow")
        ((Desert) "Desert")
        ((Tundra) "Tundra")
        ((Archipelago) "Archipelago")))

    (: ground-at (-> Land Cell Ground))
    (define (ground-at land cell)
      (vector-ref (Land-ground land) (cell-index cell)))

    (: mainland? (-> Land Cell Bool))
    (define (mainland? land cell)
      (vector-ref (Land-mainland land) (cell-index cell)))

    ;; Seeds are 1 to 65535; any integer maps into that range.
    (: land-seed (-> I64 I64))
    (define (land-seed seed)
      (+ 1 (modulo (- seed 1) 65535)))

    (: new-land (-> I64 Land))
    (define (new-land seed)
      (let* ((biome (biome-of seed))
             (hub (Cell (spawn-x seed) (spawn-y seed)))
             (fronts (map (lambda (front)
                            (Cell (front-x seed front) (front-y seed front)))
                          (list 0 1 2)))
             (ground (passes hub
                             fronts
                             (vector-generate (* map-size map-size)
                                              (lambda (index)
                                                (first-ground biome
                                                              seed
                                                              (index-cell
                                                               index))))))
             (starter (starter-cell seed hub)))
        (Land seed
              biome
              hub
              starter
              ground
              (joined ground hub (lambda (g) (match g ((Water) #f) (_ #t))))
              (Cons (Site starter 2) (crystal-sites seed hub fronts ground))
              fronts)))

    ;; The cells joined to the hub through ground that `crosses?` accepts.
    (: joined (-> (Vector Ground) Cell (-> Ground Bool) (Vector Bool)))
    (define (joined ground hub crosses?)
      (vector-map (lambda (steps) (>= steps 0))
                  (distance-field (vector-map crosses? ground) (list hub))))

    ;; ---- Hashing ----

    ;; Seeds and the keys derived from them stay below 2^18 and strides below
    ;; 2^10, so the product never overflows.
    (: map-offset (-> I64 I64 I64 I64))
    (define (map-offset seed stride count)
      (remainder (remainder (* seed stride) 65521) count))

    ;; Scrambles a value into 0 to 2^31 - 1. Each product is of two numbers
    ;; below 2^31, so it stays below 2^62 and both hosts agree.
    (: mix (-> I64 I64))
    (define (mix value)
      (let* ((x (i64-and value 2147483647))
             (x (i64-and (* (i64-xor x (i64-shift-right/logical x 16)) 73244475)
                         2147483647))
             (x (i64-and (* (i64-xor x (i64-shift-right/logical x 16)) 73244475)
                         2147483647)))
        (i64-xor x (i64-shift-right/logical x 16))))

    ;; A value for (x, y) under the seed and a key naming its use.
    (: hash (-> I64 I64 I64 I64 I64))
    (define (hash seed key x y)
      (mix (+ (mix (+ (mix (+ (* seed 64) key)) x)) (* y 65536))))

    ;; One of `items` chosen by the seed and a key, if there are any.
    (: pick (All (A) (-> I64 I64 (List A) (Option A))))
    (define (pick seed key items)
      (if (null? items)
          (None)
          (Some
           (list-ref items (remainder (hash seed key 0 0) (length items))))))

    ;; ---- The hub and the nest fronts ----

    ;; The hub sits within four cells of the map's center. Rejection keeps
    ;; that a disc; each attempt derives a new seed, with no random state.
    (: spawn-offset (-> I64 I64 Bool I64))
    (define (spawn-offset seed attempt horizontal)
      (let ((x (- (map-offset seed 73 9) 4)) (y (- (map-offset seed 151 9) 4)))
        (cond ((<= (+ (* x x) (* y y)) 16) (if horizontal x y))
              ((= attempt 23) 0)
              (else (spawn-offset (remainder (+ (* seed 25173) 13849) 65521)
                                  (+ attempt 1)
                                  horizontal)))))

    (: spawn-x (-> I64 I64))
    (define (spawn-x seed)
      (+ (quotient map-size 2) (spawn-offset seed 0 #t)))

    (: spawn-y (-> I64 I64))
    (define (spawn-y seed)
      (+ (quotient map-size 2) (spawn-offset seed 0 #f)))

    ;; The first front lies 20 to 25 cells out along a seeded axis.
    (: nest-offset (-> I64 Bool I64))
    (define (nest-offset seed horizontal)
      (let ((direction (map-offset seed 67 4))
            (major (+ 20 (map-offset seed 173 6)))
            (minor (- (map-offset seed 227 9) 4)))
        (if (= (remainder direction 2) (if horizontal 0 1))
            (if (< direction 2) major (- 0 major))
            minor)))

    ;; The other two fronts are integer rotations of the first by 120 degrees.
    (: front-offset (-> I64 I64 Bool I64))
    (define (front-offset seed front horizontal)
      (let ((x (nest-offset seed #t))
            (y (nest-offset seed #f))
            (turn (if (= front 1) 866 -866)))
        (cond ((= front 0) (if horizontal x y))
              (horizontal (quotient (- (* -500 x) (* turn y)) 1000))
              (else (quotient (+ (* turn x) (* -500 y)) 1000)))))

    (: front-x (-> I64 I64 I64))
    (define (front-x seed front)
      (+ (spawn-x seed) (front-offset seed front #t)))

    (: front-y (-> I64 I64 I64))
    (define (front-y seed front)
      (+ (spawn-y seed) (front-offset seed front #f)))

    ;; ---- Noise ----

    ;; Smooth noise from 0 to 255: random values on a lattice `scale` cells
    ;; apart, blended between the four around each cell with eased weights
    ;; in 256ths, so features have rounded edges instead of diamonds.
    (: noise (-> I64 I64 I64 I64 I64 I64))
    (define (noise seed key scale x y)
      (let ((i (quotient x scale)) (j (quotient y scale))
            (u (ease (remainder x scale) scale))
            (v (ease (remainder y scale) scale)))
        (quotient (+ (* (- 256 v)
                        (+ (* (- 256 u) (corner seed key i j))
                           (* u (corner seed key (+ i 1) j))))
                     (* v
                        (+ (* (- 256 u) (corner seed key i (+ j 1)))
                           (* u (corner seed key (+ i 1) (+ j 1))))))
                  65536)))

    (: corner (-> I64 I64 I64 I64 I64))
    (define (corner seed key i j)
      (remainder (hash seed key i j) 256))

    ;; 3t^2 - 2t^3 for t = `step` of `scale`, in 256ths.
    (: ease (-> I64 I64 I64))
    (define (ease step scale)
      (let ((t (quotient (* 256 step) scale)))
        (quotient (* (* t t) (- 768 (* 2 t))) 65536)))

    ;; Broad shapes from a coarse lattice with detail from a fine one,
    ;; sampled through a warp of up to five cells so lattice lines never
    ;; show as straight edges. Coordinates shift by 64 to stay positive.
    (: field (-> I64 I64 I64 I64 I64))
    (define (field seed key x y)
      (let ((u (+ x
                  (+ 64
                     (quotient (- (noise seed 40 7 (+ x 64) (+ y 64)) 128)
                               24))))
            (v (+ y
                  (+ 64
                     (quotient (- (noise seed 41 7 (+ x 64) (+ y 64)) 128)
                               24)))))
        (quotient (+ (* 2 (noise seed key 10 u v)) (noise seed (+ key 1) 4 u v))
                  3)))

    ;; Near the middle of a field's range: thin winding lines.
    (: crest? (-> I64 I64 I64 I64 I64 Bool))
    (define (crest? seed key width x y)
      (< (abs (- (field seed key x y) 128)) width))

    ;; ---- Biomes ----

    (: biome-of (-> I64 Biome))
    (define (biome-of seed)
      (let ((choice (remainder (mix (+ seed 7)) 4)))
        (cond ((= choice 0) (Meadow))
              ((= choice 1) (Desert))
              ((= choice 2) (Tundra))
              (else (Archipelago)))))

    ;; Meadows have lakes where it is wet and mountains where it is high.
    ;; Deserts have no water: mesas where it is high, and canyon walls
    ;; winding between them broken by gaps. Tundra has frozen lakes,
    ;; mountains and scattered boulders. An archipelago is sea but for
    ;; the high ground, with rock on the highest.
    (: wild-ground (-> Biome I64 Cell Ground))
    (define (wild-ground biome seed cell)
      (let* ((x (Cell-x cell))
             (y (Cell-y cell))
             (height (field seed 1 x y))
             (wet (field seed 3 x y)))
        (match biome
          ((Meadow)
           (cond ((< wet 88) (Water)) ((> height 168) (Rock)) (else (Open))))
          ((Desert)
           (cond ((> height 172) (Rock))
                 ((and (crest? seed 5 9 x y) (< wet 150)) (Rock))
                 (else (Open))))
          ((Tundra)
           (cond ((< wet 92) (Ice))
                 ((> height 176) (Rock))
                 ((= (remainder (hash seed 7 x y) 17) 0) (Rock))
                 (else (Open))))
          ((Archipelago)
           (cond ((< height 138) (Water))
                 ((> height 196) (Rock))
                 (else (Open)))))))

    ;; ---- Clearings ----

    ;; The hub stands in open ground four cells around, and each nest in
    ;; open ground five cells around.
    (: first-ground (-> Biome I64 Cell Ground))
    (define (first-ground biome seed cell)
      (if (cleared? seed cell) (Open) (wild-ground biome seed cell)))

    (: cleared? (-> I64 Cell Bool))
    (define (cleared? seed cell)
      (or (within? cell (Cell (spawn-x seed) (spawn-y seed)) 4)
          (any? (lambda (front)
                  (within? cell
                           (Cell (front-x seed front) (front-y seed front))
                           5))
                (list 0 1 2))))

    ;; ---- Passes ----

    ;; Each front in turn opens the blocked cells on the way to the hub that
    ;; crosses fewest of them, so a front already joined opens nothing.
    (: passes (-> Cell (List Cell) (Vector Ground) (Vector Ground)))
    (define (passes hub fronts ground)
      (fold-left (lambda (ground front)
                   (open-cells ground
                               (crossing-path (vector-map walkable? ground)
                                              (list hub)
                                              front)))
                 ground
                 fronts))

    (: walkable? (-> Ground Bool))
    (define (walkable? ground)
      (match ground
        ((Open) #t)
        ((Ice) #t)
        (_ #f)))

    (: open-cells (-> (Vector Ground) (List Cell) (Vector Ground)))
    (define (open-cells ground cells)
      (fold-left
       (lambda (ground cell) (vector-set ground (cell-index cell) (Open)))
       ground
       cells))

    ;; ---- Crystal sites ----

    ;; The starter is one of the twenty cells more than three and at most
    ;; four cells from the hub, all in its clearing.
    (: starter-cell (-> I64 Cell Cell))
    (define (starter-cell seed hub)
      (let ((cells (ring hub 3 4)))
        (list-ref cells (remainder (hash seed 10 0 0) (length cells)))))

    ;; Past the starter, a site needs open ground the hub can wire toward,
    ;; over water and ice but not through rock, and clear of the nests: a
    ;; second 8 to 11 cells out and a richer third 12 to 15 out, apart from
    ;; it; a few across the map; and one near most fronts, so following an
    ;; attack back to its nest leads to richer ground. A cell holds at most
    ;; one site; the first listed keeps it.
    (: crystal-sites (-> I64 Cell (List Cell) (Vector Ground) (List Site)))
    (define (crystal-sites seed hub fronts ground)
      (let* ((site? (site-cell? ground
                                (joined ground
                                        hub
                                        (lambda (g)
                                          (match g ((Rock) #f) (_ #t))))
                                fronts))
             (second (pick seed 11 (filter site? (ring hub 7 11))))
             (third (pick seed
                          12
                          (filter (lambda (cell)
                                    (and (site? cell) (apart? cell second)))
                                  (ring hub 11 15)))))
        (delete-duplicates (lambda (a b) (cell=? (Site-cell a) (Site-cell b)))
                           (concatenate (list (site second 3)
                                              (site third 6)
                                              (regional-sites seed hub site?)
                                              (front-sites seed
                                                           fronts
                                                           site?))))))

    ;; Open ground the hub can wire toward, at least five cells from every
    ;; front.
    (: site-cell? (-> (Vector Ground) (Vector Bool) (List Cell) (-> Cell Bool)))
    (define (site-cell? ground wired fronts)
      (lambda (cell)
        (and (match (vector-ref ground (cell-index cell)) ((Open) #t) (_ #f))
             (vector-ref wired (cell-index cell))
             (not (any? (lambda (front) (within? cell front 4)) fronts)))))

    (: site (-> (Option Cell) I64 (List Site)))
    (define (site cell rate)
      (match cell
        ((Some cell) (list (Site cell rate)))
        ((None) (Nil))))

    (: apart? (-> Cell (Option Cell) Bool))
    (define (apart? cell other)
      (match other
        ((Some other) (not (within? cell other 8)))
        ((None) #t)))

    ;; The cells on the map more than `inner` and at most `outer` cells from
    ;; the center.
    (: ring (-> Cell I64 I64 (List Cell)))
    (define (ring center inner outer)
      (let ((side (+ (* 2 outer) 1)))
        (filter (lambda (cell)
                  (and (in-bounds? cell)
                       (within? cell center outer)
                       (not (within? cell center inner))))
                (map (lambda (i)
                       (Cell (+ (Cell-x center) (- (remainder i side) outer))
                             (+ (Cell-y center) (- (quotient i side) outer))))
                     (iota (* side side))))))

    ;; Two regions in five of the 16-cell regions hold a site yielding 2 to
    ;; 6, more than 15 cells from the hub.
    (: regional-sites (-> I64 Cell (-> Cell Bool) (List Site)))
    (define (regional-sites seed hub site?)
      (concatenate (map (lambda (region)
                          (let ((rx (* 16 (remainder region 5)))
                                (ry (* 16 (quotient region 5))))
                            (if (< (remainder (hash seed 13 rx ry) 5) 2)
                                (site (pick (+ seed region)
                                            14
                                            (filter (lambda (cell)
                                                      (and (site? cell)
                                                           (not (within? cell
                                                                         hub
                                                                         15))))
                                                    (region-cells rx ry)))
                                      (+ 2 (remainder (hash seed 15 rx ry) 5)))
                                (Nil))))
                        (iota 25))))

    (: region-cells (-> I64 I64 (List Cell)))
    (define (region-cells rx ry)
      (map (lambda (i) (Cell (+ rx (remainder i 16)) (+ ry (quotient i 16))))
           (iota 256)))

    ;; Three fronts in four have a site yielding 4, 6 to 9 cells out.
    (: front-sites (-> I64 (List Cell) (-> Cell Bool) (List Site)))
    (define (front-sites seed fronts site?)
      (concatenate (map-indexed (lambda (index front)
                                  (if (< (remainder (hash seed 16 index 0) 4) 3)
                                      (site (pick (+ seed index)
                                                  17
                                                  (filter site?
                                                          (ring front 5 9)))
                                            4)
                                      (Nil)))
                                fronts)))

    ))
