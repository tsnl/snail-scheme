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
   Land
   new-land
   land-seed
   ground-at
   mainland?
   nest-rate
   reserve-per-rate)
  (import
   (snail core base)
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

    (define reserve-per-rate (→ I64) 300)

    ;; The crystal beneath each nest, exposed when the nest is destroyed.
    (define nest-rate (→ I64) 8)

    (define (biome-name (biome Biome)) (→ String)
      (match biome
        ((Meadow) "Meadow")
        ((Desert) "Desert")
        ((Tundra) "Tundra")
        ((Archipelago) "Archipelago")))

    (define (ground-at (land Land) (cell Cell)) (→ Ground)
      (vector-ref (● land ground) (cell-index cell)))

    (define (mainland? (land Land) (cell Cell)) (→ Bool)
      (vector-ref (● land mainland) (cell-index cell)))

    ;; Seeds are 1 to 65535; any integer maps into that range.
    (define (land-seed (seed I64)) (→ I64)
      (+ 1 (modulo (- seed 1) 65535)))

    (define (new-land (seed I64)) (→ Land)
      (let* ((biome (biome-of seed))
             (hub (Cell (spawn-x seed) (spawn-y seed)))
             (fronts
              (map (lambda (front) (Cell (front-x seed front) (front-y seed front))) (list 0 1 2)))
             (ground (passes hub
                             fronts
                             (vector-generate (* map-size map-size)
                                              (lambda (index)
                                                (first-ground biome seed (index-cell index))))))
             (starter (starter-cell seed hub)))
        (Land seed
              biome
              hub
              starter
              ground
              (joined ground hub (lambda (g) (match g ((Water) #f) (_ #t))))
              (Cons (Site starter 2) (crystal-sites seed hub fronts ground)) fronts)))

    ;; The cells joined to the hub through ground that `crosses?` accepts.
    (define (joined (ground (Vector Ground)) (hub Cell) (crosses? (Fn Ground → Bool)))
      (→ (Vector Bool))
      (vector-map (lambda (steps) (>= steps 0))
                  (distance-field (vector-map crosses? ground) (list hub))))

    ;; ---- Hashing ----

    ;; Seeds and the keys derived from them stay below 2^18 and strides below
    ;; 2^10, so the product never overflows.
    (define (map-offset (seed I64) (stride I64) (count I64)) (→ I64)
      (remainder (remainder (* seed stride) 65521) count))

    ;; Scrambles a value into 0 to 2^31 - 1. Each product is of two numbers
    ;; below 2^31, so it stays below 2^62 and both hosts agree.
    (define (mix (value I64)) (→ I64)
      (let* ((x (i64-and value 2147483647))
             (x (i64-and (* (i64-xor x (i64-shift-right/logical x 16)) 73244475) 2147483647))
             (x (i64-and (* (i64-xor x (i64-shift-right/logical x 16)) 73244475) 2147483647)))
        (i64-xor x (i64-shift-right/logical x 16))))

    ;; A value for (x, y) under the seed and a key naming its use.
    (define (hash (seed I64) (key I64) (x I64) (y I64)) (→ I64)
      (mix (+ (mix (+ (mix (+ (* seed 64) key)) x)) (* y 65536))))

    ;; One of `items` chosen by the seed and a key, if there are any.
    (define (pick (seed I64) (key I64) (items (List A))) (→ (Option A)) (∀ A) (⊨ (Copy A))
      (if (null? items)
          (None)
          (Some (list-ref items (remainder (hash seed key 0 0) (length items))))))

    ;; ---- The hub and the nest fronts ----

    ;; The hub sits within four cells of the map's center. Rejection keeps
    ;; that a disc; each attempt derives a new seed, with no random state.
    (define (spawn-offset (seed I64) (attempt I64) (horizontal Bool)) (→ I64)
      (let ((x (- (map-offset seed 73 9) 4)) (y (- (map-offset seed 151 9) 4)))
        (cond ((<= (+ (* x x) (* y y)) 16) (if horizontal x y))
              ((= attempt 23) 0)
              (else (spawn-offset (remainder (+ (* seed 25173) 13849) 65521)
                                  (+ attempt 1)
                                  horizontal)))))

    (define (spawn-x (seed I64)) (→ I64)
      (+ (quotient map-size 2) (spawn-offset seed 0 #t)))

    (define (spawn-y (seed I64)) (→ I64)
      (+ (quotient map-size 2) (spawn-offset seed 0 #f)))

    ;; The first front lies 20 to 25 cells out along a seeded axis.
    (define (nest-offset (seed I64) (horizontal Bool)) (→ I64)
      (let ((direction (map-offset seed 67 4))
            (major (+ 20 (map-offset seed 173 6)))
            (minor (- (map-offset seed 227 9) 4)))
        (if (= (remainder direction 2) (if horizontal 0 1))
            (if (< direction 2) major (- 0 major))
            minor)))

    ;; The other two fronts are integer rotations of the first by 120 degrees.
    (define (front-offset (seed I64) (front I64) (horizontal Bool)) (→ I64)
      (let ((x (nest-offset seed #t)) (y (nest-offset seed #f)) (turn (if (= front 1) 866 -866)))
        (cond ((= front 0) (if horizontal x y))
              (horizontal (quotient (- (* -500 x) (* turn y)) 1000))
              (else (quotient (+ (* turn x) (* -500 y)) 1000)))))

    (define (front-x (seed I64) (front I64)) (→ I64)
      (+ (spawn-x seed) (front-offset seed front #t)))

    (define (front-y (seed I64) (front I64)) (→ I64)
      (+ (spawn-y seed) (front-offset seed front #f)))

    ;; ---- Noise ----

    ;; Smooth noise from 0 to 255: random values on a lattice `scale` cells
    ;; apart, blended between the four around each cell with eased weights
    ;; in 256ths, so features have rounded edges instead of diamonds.
    (define (noise (seed I64) (key I64) (scale I64) (x I64) (y I64)) (→ I64)
      (let ((i (quotient x scale)) (j (quotient y scale))
            (u (ease (remainder x scale) scale)) (v (ease (remainder y scale) scale)))
        (quotient
         (+ (* (- 256 v) (+ (* (- 256 u) (corner seed key i j)) (* u (corner seed key (+ i 1) j))))
            (* v
               (+ (* (- 256 u) (corner seed key i (+ j 1)))
                  (* u (corner seed key (+ i 1) (+ j 1))))))
         65536)))

    (define (corner (seed I64) (key I64) (i I64) (j I64)) (→ I64)
      (remainder (hash seed key i j) 256))

    ;; 3t^2 - 2t^3 for t = `step` of `scale`, in 256ths.
    (define (ease (step I64) (scale I64)) (→ I64)
      (let ((t (quotient (* 256 step) scale)))
        (quotient (* (* t t) (- 768 (* 2 t))) 65536)))

    ;; Broad shapes from a coarse lattice with detail from a fine one,
    ;; sampled through a warp of up to five cells so lattice lines never
    ;; show as straight edges. Coordinates shift by 64 to stay positive.
    (define (field (seed I64) (key I64) (x I64) (y I64)) (→ I64)
      (let ((u (+ x (+ 64 (quotient (- (noise seed 40 7 (+ x 64) (+ y 64)) 128) 24))))
            (v (+ y (+ 64 (quotient (- (noise seed 41 7 (+ x 64) (+ y 64)) 128) 24)))))
        (quotient (+ (* 2 (noise seed key 10 u v)) (noise seed (+ key 1) 4 u v)) 3)))

    ;; Near the middle of a field's range: thin winding lines.
    (define (crest? (seed I64) (key I64) (width I64) (x I64) (y I64)) (→ Bool)
      (< (abs (- (field seed key x y) 128)) width))

    ;; ---- Biomes ----

    (define (biome-of (seed I64)) (→ Biome)
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
    (define (wild-ground (biome Biome) (seed I64) (cell Cell)) (→ Ground)
      (let* ((x (● cell x))
             (y (● cell y))
             (height (field seed 1 x y))
             (wet (field seed 3 x y)))
        (match biome
          ((Meadow) (cond ((< wet 88) (Water)) ((> height 168) (Rock)) (else (Open))))
          ((Desert)
           (cond ((> height 172) (Rock))
                 ((and (crest? seed 5 9 x y) (< wet 150)) (Rock))
                 (else (Open))))
          ((Tundra)
           (cond ((< wet 92) (Ice))
                 ((> height 176) (Rock))
                 ((= (remainder (hash seed 7 x y) 17) 0) (Rock))
                 (else (Open))))
          ((Archipelago) (cond ((< height 138) (Water)) ((> height 196) (Rock)) (else (Open)))))))

    ;; ---- Clearings ----

    ;; The hub stands in open ground four cells around, and each nest in
    ;; open ground five cells around.
    (define (first-ground (biome Biome) (seed I64) (cell Cell)) (→ Ground)
      (if (cleared? seed cell) (Open) (wild-ground biome seed cell)))

    (define (cleared? (seed I64) (cell Cell)) (→ Bool)
      (or (within? cell (Cell (spawn-x seed) (spawn-y seed)) 4)
          (any? (lambda (front) (within? cell (Cell (front-x seed front) (front-y seed front)) 5))
                (list 0 1 2))))

    ;; ---- Passes ----

    ;; Each front in turn opens the blocked cells on the way to the hub that
    ;; crosses fewest of them, so a front already joined opens nothing.
    (define (passes (hub Cell) (fronts (List Cell)) (ground (Vector Ground))) (→ (Vector Ground))
      (fold-left (lambda (ground front)
                   (open-cells ground
                               (crossing-path (vector-map walkable? ground) (list hub) front)))
                 ground
                 fronts))

    (define (walkable? (ground Ground)) (→ Bool)
      (match ground
        ((Open) #t)
        ((Ice) #t)
        (_ #f)))

    (define (open-cells (ground (Vector Ground)) (cells (List Cell))) (→ (Vector Ground))
      (fold-left (lambda (ground cell) (vector-set ground (cell-index cell) (Open))) ground cells))

    ;; ---- Crystal sites ----

    ;; The starter is one of the twenty cells more than three and at most
    ;; four cells from the hub, all in its clearing.
    (define (starter-cell (seed I64) (hub Cell)) (→ Cell)
      (let ((cells (ring hub 3 4)))
        (list-ref cells (remainder (hash seed 10 0 0) (length cells)))))

    ;; Past the starter, a site needs open ground the hub can wire toward,
    ;; over water and ice but not through rock, and clear of the nests: a
    ;; second 8 to 11 cells out and a richer third 12 to 15 out, apart from
    ;; it; a few across the map; and one near most fronts, so following an
    ;; attack back to its nest leads to richer ground. A cell holds at most
    ;; one site; the first listed keeps it.
    (define (crystal-sites (seed I64) (hub Cell) (fronts (List Cell)) (ground (Vector Ground)))
      (→ (List Site))
      (let* ((site? (site-cell? ground
                                (joined ground hub (lambda (g) (match g ((Rock) #f) (_ #t))))
                                fronts))
             (second (pick seed 11 (filter site? (ring hub 7 11))))
             (third (pick seed
                          12
                          (filter (lambda (cell) (and (site? cell) (apart? cell second)))
                                  (ring hub 11 15)))))
        (delete-duplicates (lambda (a b) (cell=? (● a cell) (● b cell)))
                           (concatenate (list (site second 3)
                                              (site third 6)
                                              (regional-sites seed hub site?)
                                              (front-sites seed fronts site?))))))

    ;; Open ground the hub can wire toward, at least five cells from every
    ;; front.
    (define (site-cell? (ground (Vector Ground)) (wired (Vector Bool)) (fronts (List Cell)))
      (→ (Fn Cell → Bool))
      (lambda (cell)
        (and (match (vector-ref ground (cell-index cell)) ((Open) #t) (_ #f))
             (vector-ref wired (cell-index cell))
             (not (any? (lambda (front) (within? cell front 4)) fronts)))))

    (define (site (cell (Option Cell)) (rate I64)) (→ (List Site))
      (match cell
        ((Some cell) (list (Site cell rate)))
        ((None) (Nil))))

    (define (apart? (cell Cell) (other (Option Cell))) (→ Bool)
      (match other
        ((Some other) (not (within? cell other 8)))
        ((None) #t)))

    ;; The cells on the map more than `inner` and at most `outer` cells from
    ;; the center.
    (define (ring (center Cell) (inner I64) (outer I64)) (→ (List Cell))
      (let ((side (+ (* 2 outer) 1)))
        (filter (lambda (cell)
                  (and (in-bounds? cell)
                       (within? cell center outer)
                       (not (within? cell center inner))))
                (map (lambda (i)
                       (Cell (+ (● center x) (- (remainder i side) outer))
                             (+ (● center y) (- (quotient i side) outer))))
                     (iota (* side side))))))

    ;; Two regions in five of the 16-cell regions hold a site yielding 2 to
    ;; 6, more than 15 cells from the hub.
    (define (regional-sites (seed I64) (hub Cell) (site? (Fn Cell → Bool))) (→ (List Site))
      (concatenate (map (lambda (region)
                          (let ((rx (* 16 (remainder region 5))) (ry (* 16 (quotient region 5))))
                            (if (< (remainder (hash seed 13 rx ry) 5) 2)
                                (site (pick (+ seed region)
                                            14
                                            (filter (lambda (cell)
                                                      (and (site? cell)
                                                           (not (within? cell hub 15))))
                                                    (region-cells rx ry)))
                                      (+ 2 (remainder (hash seed 15 rx ry) 5)))
                                (Nil))))
                        (iota 25))))

    (define (region-cells (rx I64) (ry I64)) (→ (List Cell))
      (map (lambda (i) (Cell (+ rx (remainder i 16)) (+ ry (quotient i 16)))) (iota 256)))

    ;; Three fronts in four have a site yielding 4, 6 to 9 cells out.
    (define (front-sites (seed I64) (fronts (List Cell)) (site? (Fn Cell → Bool)))
      (→ (List Site))
      (concatenate (map-indexed (lambda (index front)
                                  (if (< (remainder (hash seed 16 index 0) 4) 3)
                                      (site (pick (+ seed index) 17 (filter site? (ring front 5 9)))
                                            4)
                                      (Nil)))
                                fronts)))

    ))
