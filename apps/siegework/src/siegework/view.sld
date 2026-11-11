;; What the player sees, in the original Siegework's style: sunny ground in
;; its biome's colors on a teal world under a blue sky, warm cream and
;; brass buildings with deep blue trim, violet crystals and crystalline
;; enemies, and glowing wires carrying pulses of energy home.
;;
;; Models are lists of parts given as in the original, with z up and y
;; north, each shape centered on its offset; `part` turns them into items
;; standing on the ground in the host's coordinates, x east, y up and z
;; south. Batches are versioned so the host redraws only what changed;
;; moving things are sent once a tick with where they were, and the host
;; moves them between ticks.
(define-library (siegework view)
  (export
   view-game)
  (import
   (snail core base)
   (snail shell app)
   (snail shell math)
   (siegework grid)
   (siegework terrain)
   (siegework world)
   (siegework colony)
   (siegework siege)
   (siegework game))
  (begin

    ;; ---- Palette ----

    ;; A color, and how much it glows instead of taking the light.
    (struct Paint
      ((color I32)
       (glow F32)))

    (define steel (Paint (rgb 28 62 91) 0.0))
    (define cream (Paint (rgb 255 244 203) 0.0))
    (define brass (Paint (rgb 255 185 49) 0.05))
    (define cyan (Paint (rgb 35 242 195) 0.25))
    (define blue (Paint (rgb 54 126 238) 0.1))
    (define rust (Paint (rgb 245 99 66) 0.05))
    (define warning (Paint (rgb 255 78 96) 0.35))
    (define violet (Paint (rgb 187 109 244) 0.1))
    (define gemstone (Paint (rgb 119 59 229) 0.35))
    (define gem-light (Paint (rgb 188 139 255) 0.3))
    (define indigo (Paint (rgb 68 49 178) 0.25))
    (define lamp (Paint (rgb 255 244 142) 0.9))
    (define shadow (Paint (rgb 70 78 92) 0.0))

    (define sky (→ I32) (rgb 28 151 223))

    ;; ---- Parts ----

    ;; A shape centered at (x, y, z) with z up and y north, and size w by d
    ;; by h, as an item standing in the host's coordinates.
    (define (part (mesh Mesh) (paint Paint) (x F32) (y F32) (z F32) (w F32) (d F32) (h F32))
      (→ Item)
      (Item-glow-set
       (item mesh (Vec3 x (- z (/ h 2.0)) (negate y)) (Vec3 w h d) 0.0 (::color paint))
       (::glow paint)))

    (define (block (paint Paint) (x F32) (y F32) (z F32) (w F32) (d F32) (h F32)) (→ Item)
      (part (Box) paint x y z w d h))

    ;; A flat w by d square at height z.
    (define (flat (paint Paint) (x F32) (y F32) (z F32) (w F32) (d F32)) (→ Item)
      (Item-glow-set (item (Tile) (Vec3 x z (negate y)) (Vec3 w 1.0 d) 0.0 (::color paint))
                     (::glow paint)))

    ;; Scales the positions and sizes of standing parts.
    (define (resize (parts (List Item)) (kx F32) (ky F32) (kz F32)) (→ (List Item))
      (map (lambda (it)
             (let* ((p (::position it))
                    (s (::scale it))
                    (moved (Vec3 (* kx (::x p)) (* ky (::y p)) (* kz (::z p)))))
               (Item-from-set (Item-scale-set (Item-position-set it moved)
                                              (Vec3 (* kx (::x s))
                                                    (* ky (::y s))
                                                    (* kz (::z s))))
                              moved)))
           parts))

    ;; Turns parts by `yaw` about their origin and moves them to `origin`.
    (define (place (parts (List Item)) (origin Vec3) (yaw F32)) (→ (List Item))
      (map (lambda (it)
             (Item-yaw-set
              (Item-from-set (Item-position-set it (turned (::position it) origin yaw))
                             (turned (::from it) origin yaw))
              (+ yaw (::yaw it))))
           parts))

    (define (turned (p Vec3) (origin Vec3) (yaw F32)) (→ Vec3)
      (let ((c (f64->f32 (cos (f32->f64 yaw)))) (s (f64->f32 (sin (f32->f64 yaw)))))
        (Vec3 (+ (::x origin) (+ (* c (::x p)) (* s (::z p))))
              (+ (::y origin) (::y p))
              (+ (::z origin) (- (* c (::z p)) (* s (::x p)))))))

    ;; Parts that move from one place to another over the coming tick.
    (define (travel (parts (List Item)) (from Vec3) (to Vec3) (yaw F32)) (→ (List Item))
      (map (lambda (pair) (Item-from-set (::second pair) (::position (::first pair))))
           (zip (place parts from yaw) (place parts to yaw))))

    (define (cell-point (cell Cell) (height F32)) (→ Vec3)
      (Vec3 (i64->f32 (::x cell)) height (i64->f32 (::y cell))))

    (define (at-cell (cell Cell) (parts (List Item))) (→ (List Item))
      (place parts (cell-point cell 0.0) 0.0))

    (define (between (a Vec3) (b Vec3) (t F32)) (→ Vec3)
      (Vec3 (+ (::x a) (* t (- (::x b) (::x a))))
            (+ (::y a) (* t (- (::y b) (::y a))))
            (+ (::z a) (* t (- (::z b) (::z a))))))

    (define (atan2-f32 (y F32) (x F32)) (→ F32)
      (f64->f32 (atan2 (f32->f64 y) (f32->f64 x))))

    ;; ---- Ground ----

    ;; A biome's ground colors: open ground in three sunny tones where
    ;; powered buildings see and a fourth where they no longer do, sand for
    ;; shores where the biome has them, then water, ice, dug rock and rock.
    (struct Tileset
      ((light I32)
       (middle I32)
       (deep I32)
       (unseen I32)
       (shore (Option I32))
       (water I32)
       (ice I32)
       (dug I32)
       (rock I32)))

    (define (tileset (biome Biome)) (→ Tileset)
      (match biome
        ((Meadow) (Tileset (rgb 154 224 74) (rgb 121 211 78) (rgb 95 190 70) (rgb 67 144 113) (None)
                           (rgb 54 126 238) (rgb 190 232 246) (rgb 174 139 95) (rgb 196 204 179)))
        ((Desert)
         (Tileset (rgb 250 222 160) (rgb 241 206 136) (rgb 230 190 116) (rgb 168 150 110) (None)
                  (rgb 54 126 238) (rgb 190 232 246) (rgb 196 150 104) (rgb 212 120 78)))
        ((Tundra)
         (Tileset (rgb 250 252 255) (rgb 234 242 248) (rgb 220 232 242) (rgb 138 168 186) (None)
                  (rgb 54 126 238) (rgb 160 220 242) (rgb 150 142 134) (rgb 122 136 154)))
        ((Archipelago)
         (Tileset (rgb 142 224 98)
                  (rgb 114 208 92)
                  (rgb 90 188 86)
                  (rgb 67 144 113)
                  (Some (rgb 244 222 158))
                  (rgb 36 128 214) (rgb 190 232 246) (rgb 174 139 95) (rgb 116 110 112)))))

    ;; Open ground out of sight is faded. In sight it is a shore beside
    ;; explored water where the biome has shores, and otherwise shaded in a
    ;; fixed pattern.
    (define (open-paint (world World) (tiles Tileset) (cell Cell)) (→ Paint)
      (Paint (if (visible? world cell)
                 (match (::shore tiles)
                   ((Some shore) (if (beside-water? world cell) shore (open-tone tiles cell)))
                   ((None) (open-tone tiles cell)))
                 (::unseen tiles))
             0.0))

    (define (open-tone (tiles Tileset) (cell Cell)) (→ I32)
      (let ((x (::x cell)) (y (::y cell)))
        (cond ((= (remainder (+ (* x 13) (* y 7)) 5) 0) (::light tiles))
              ((= (remainder (+ x (* y 3)) 3) 0) (::deep tiles))
              (else (::middle tiles)))))

    ;; Unexplored water does not count, so a shore never gives it away.
    (define (beside-water? (world World) (cell Cell)) (→ Bool)
      (any? (lambda (n)
              (and (explored? world n)
                   (match (ground-at (::land world) n) ((Water) #t) (_ #f))))
            (neighbors cell)))

    ;; Rock is a grey peak in meadows and on islands, a flat-topped mesa in
    ;; the desert, and a snow-capped peak in the tundra. Dug rock is a floor.
    (define (ground-parts (world World) (cell Cell)) (→ (List Item))
      (let* ((biome (::biome (::land world)))
             (tiles (tileset biome))
             (floor (flat (open-paint world tiles cell) 0.0 0.0 0.0 0.99 0.99)))
        (match (ground-at (::land world) cell)
          ((Open) (list floor))
          ((Water) (list (flat (Paint (::water tiles) 0.1) 0.0 0.0 0.012 0.99 0.99)))
          ((Ice) (list (flat (Paint (::ice tiles) 0.2) 0.0 0.0 0.008 0.99 0.99)))
          ((Rock) (if (opened? world cell)
                      (list (flat (Paint (::dug tiles) 0.0) 0.0 0.0 0.0 0.99 0.99))
                      (Cons floor (rock-parts biome (Paint (::rock tiles) 0.0))))))))

    (define (rock-parts (biome Biome) (paint Paint)) (→ (List Item))
      (match biome
        ((Desert) (list (block paint 0.0 0.0 0.3 0.98 0.98 0.6)))
        ((Tundra)
         (list (part (Pyramid) paint 0.0 0.0 0.425 1.0 0.94 0.85)
               (part (Pyramid) (Paint (rgb 250 252 255) 0.1) 0.0 0.0 0.7 0.42 0.4 0.3)))
        (_ (list (part (Pyramid) paint 0.0 0.0 0.425 1.0 0.94 0.85)))))

    ;; The world's base beneath the map, with a cream rim.
    (define (base-items) (→ (List Item))
      (let* ((size (i64->f32 map-size)) (middle (- (/ size 2.0) 0.5)))
        (list (Item-glow-set
               (item (Box) (Vec3 middle -0.7 middle) (Vec3 size 0.69 size) 0.0 (rgb 31 96 119))
               0.7)
              (block cream -0.5 (negate middle) 0.02 0.12 size 0.06)
              (block cream (- size 0.5) (negate middle) 0.02 0.12 size 0.06)
              (block cream middle 0.5 0.02 size 0.12 0.06)
              (block cream middle (- 0.5 size) 0.02 size 0.12 0.06))))

    ;; Explored cells that `include?` picks.
    (define (terrain-items (world World) (include? (dyn (Fn I64 → Bool)))) (→ (List Item))
      (concatenate
       (map (lambda (index) (at-cell (index-cell index) (ground-parts world (index-cell index))))
            (filter
             (lambda (index) (and (vector-ref (::explored world) index) (include? index)))
             (iota (* map-size map-size))))))

    ;; ---- Buildings ----

    ;; The hub's low roof leaves the wires' junction showing at their height.
    (define (hub-parts) (→ (List Item))
      (resize (list (block steel 0.0 0.0 0.12 3.0 3.0 0.24) (block cream 0.0 0.0 0.51 2.6 2.6 0.78)
                    (block brass -0.93 0.0 0.96 1.04 2.9 0.12)
                    (block brass 0.93 0.0 0.96 1.04 2.9 0.12)
                    (block brass 0.0 -0.93 0.96 0.82 1.04 0.12)
                    (block brass 0.0 0.93 0.96 0.82 1.04 0.12)
                    (block steel 0.0 0.0 1.08 0.18 0.18 0.36)
                    (block cyan 0.0 0.0 1.3846 0.34 0.34 0.12)
                    (block cyan 0.0 -1.31 0.55 1.5 0.04 0.32))
              1.0 0.65 1.0))

    (define (extractor-parts (level I64)) (→ (List Item))
      (resize (list (block steel 0.0 0.0 0.1 0.9 0.9 0.2)
                    (part (Tetrahedron) gemstone 0.0 -0.05 0.4 0.7 0.7 0.7)
                    (block cream -0.36 0.08 0.52 0.12 0.16 0.84)
                    (block cream 0.36 0.08 0.52 0.12 0.16 0.84)
                    (block brass 0.0 0.08 0.94 0.84 0.2 0.16)
                    (block cyan 0.0 0.0 1.125 0.24 0.24 0.12)
                    (part (Octahedron) steel 0.0 0.08 0.76 0.18 0.18 0.36)
                    (block (if (>= level 3) brass steel) -0.56 -0.15 0.12 0.2 0.42 0.24)
                    (block (if (>= level 2) brass steel) 0.56 -0.15 0.12 0.2 0.42 0.24))
              1.15 0.8 1.15))

    (define (pylon-parts (level I64)) (→ (List Item))
      (resize (concatenate
               (list (list (block steel 0.0 0.0 0.12 0.9 0.9 0.24)
                           (block blue -0.18 0.0 0.61 0.12 0.12 1.0)
                           (block blue 0.18 0.0 0.61 0.12 0.12 1.0)
                           (block cream 0.0 0.0 1.06 0.7 0.22 0.13)
                           (part (Pyramid) blue 0.0 0.0 1.35 0.46 0.46 0.5)
                           (block lamp 0.0 0.0 1.6 0.13 0.13 0.13)
                           (block brass 0.0 -0.33 0.39 0.28 0.22 0.3))
                     (if (>= level 2) (list (block cyan 0.0 0.0 1.06 0.88 0.35 0.08)) (Nil))
                     (if (>= level 3)
                         (list (block cream -0.36 0.0 0.675 0.12 0.76 0.87)
                               (block cream 0.36 0.0 0.675 0.12 0.76 0.87)
                               (block brass 0.0 0.0 1.185 0.94 0.84 0.15)
                               (block blue 0.0 -0.44 1.16 0.35 0.04 0.2))
                         (Nil))))
              1.0 0.55 1.0))

    ;; A mast at the back holds the turret's wire junction over its middle,
    ;; above the guns, at the height every wire meets.
    (define (turret-parts (level I64)) (→ (List Item))
      (append (resize (list (block steel 0.0 0.0 0.1 0.94 0.94 0.2)
                            (block steel -0.36 0.0 0.26 0.18 0.86 0.32)
                            (block steel 0.36 0.0 0.26 0.18 0.86 0.32)
                            (block rust 0.0 0.0 0.3 0.56 0.66 0.3)
                            (block cream 0.0 0.0 0.5 0.68 0.58 0.12)
                            (block (if (>= level 2) brass steel) -0.4 -0.26 0.46 0.18 0.26 0.2)
                            (block (if (>= level 3) brass steel) 0.4 -0.26 0.46 0.18 0.26 0.2))
                      1.0 0.55 1.0)
              (list (block steel 0.0 -0.42 0.56 0.08 0.08 0.72)
                    (block steel 0.0 -0.21 0.9 0.06 0.42 0.06)
                    (block cyan 0.0 0.0 0.9 0.2 0.2 0.12))))

    ;; One gun per level, stacked below the junction; each points north
    ;; until it is aimed.
    (define (cannon-parts (level I64)) (→ (List Item))
      (concatenate (map (lambda (index)
                          (place (resize (list (block rust 0.0 -0.1 0.0 0.58 0.5 0.32)
                                               (block cream 0.0 0.35 0.09 0.22 0.72 0.22)
                                               (block steel 0.0 0.75 0.09 0.15 0.42 0.15)
                                               (block brass 0.0 0.97 0.09 0.27 0.12 0.27))
                                         1.0 0.55 1.0)
                                 (Vec3 0.0 (+ 0.3 (* 0.22 (i64->f32 index))) 0.0) 0.0))
                        (iota level))))

    (define (construction-parts) (→ (List Item))
      (list (block steel 0.0 0.0 0.06 0.9 0.9 0.12) (block brass 0.0 0.0 0.22 0.43 0.43 0.32)
            (block lamp -0.4 -0.4 0.18 0.07 0.07 0.36) (block lamp 0.4 0.4 0.18 0.07 0.07 0.36)))

    (define (building-parts (kind Kind) (level I64)) (→ (List Item))
      (if (= level 0)
          (construction-parts)
          (match kind
            ((Extractor) (extractor-parts level))
            ((Pylon) (pylon-parts level))
            ((Turret) (turret-parts level)))))

    ;; An unpowered building loses its color and glow.
    (define (unpowered (parts (List Item))) (→ (List Item))
      (map (lambda (it) (Item-glow-set (Item-color-set it (::color shadow)) 0.0)) parts))

    (define (building-items (world World) (building Building)) (→ (List Item))
      (let ((parts (building-parts (::kind building) (::level building))))
        (at-cell (::cell building)
                 (if (or (not (built? building)) (powered? world (::id building)))
                     parts
                     (unpowered parts)))))

    ;; ---- Crystals and nests ----

    (define (crystal-parts) (→ (List Item))
      (list (part (Tetrahedron) gemstone -0.16 -0.04 0.217 0.62 0.62 0.686)
            (part (Tetrahedron) gem-light 0.23 0.16 0.178 0.44 0.44 0.564)
            (part (Tetrahedron) indigo 0.12 -0.28 0.124 0.32 0.32 0.392)))

    (define (shimmer-parts) (→ (List Item))
      (list (flat gemstone 0.0 0.0 0.025 1.1 1.1)
            (part (Octahedron) (Paint (rgb 232 208 255) 0.9) -0.16 -0.04 0.58 0.08 0.08 0.2)
            (part (Octahedron) gem-light 0.23 0.16 0.48 0.06 0.06 0.14)))

    ;; Crystals in explored ground with energy left, not under a building or
    ;; a living nest.
    (define (open-crystals (world World)) (→ (List Crystal))
      (filter (lambda (c) (let ((cell (::cell c)))
                            (and (explored? world cell) (> (::reserve c) 0)
                                 (match (building-at world cell) ((Some _) #f) ((None) #t))
                                 (match (nest-at world cell)
                                   ((Some nest) (= (::health nest) 0))
                                   ((None) #t)))))
              (::crystals world)))

    (define (nest-parts) (→ (List Item))
      (list (block steel 0.0 0.0 0.2 2.8 2.8 0.4) (part (Pyramid) violet 0.0 0.0 1.1 2.5 2.5 2.0)
            (part (Pyramid) cream -1.0 -1.0 1.4 0.55 0.55 2.8)
            (part (Pyramid) cream 1.0 1.0 1.4 0.55 0.55 2.8)
            (block warning 0.0 -1.24 0.6 1.1 0.08 0.7)))

    (define (nest-items (world World)) (→ (List Item))
      (concatenate (map (lambda (nest) (at-cell (::cell nest) (nest-parts)))
                        (filter (lambda (nest)
                                  (and (> (::health nest) 0) (explored? world (::cell nest))))
                                (::nests world)))))

    ;; ---- Wires and outlines ----

    (define wire-height (→ F32) 0.9)

    ;; A thin beam at wire height from one cell to another.
    (define (beam (from Cell) (to Cell) (thickness F32) (paint Paint)) (→ Item)
      (let* ((a (cell-point from (- wire-height (/ thickness 2.0))))
             (b (cell-point to (- wire-height (/ thickness 2.0))))
             (dx (- (::x b) (::x a))) (dz (- (::z b) (::z a))))
        (Item-glow-set (item (Box)
                             (between a b 0.5)
                             (Vec3 (sqrt (+ (* dx dx) (* dz dz))) thickness thickness)
                             (atan2-f32 (negate dz) dx)
                             (::color paint))
                       (::glow paint))))

    ;; Wires are thin glassy turquoise beams between powered buildings, and
    ;; grey among unpowered ones.
    (define (link-items (world World)) (→ (List Item))
      (map (lambda (wire)
             (beam (::cell (::from wire)) (::cell (::to wire)) 0.07
                   (if (powered? world (::id (::from wire)))
                       (Paint (rgb 35 242 195) 0.7)
                       (Paint (rgb 120 128 140) 0.2))))
           (::wires (::network world))))

    ;; Thin strokes along the edges of a set of cells, shifted by `lane` so
    ;; two outlines on one edge lie side by side.
    (define (outline-items (cells (Vector Bool)) (paint Paint) (lane F32)) (→ (List Item))
      (concatenate (map (lambda (index) (edge-strokes cells (index-cell index) paint lane))
                        (filter (lambda (index) (vector-ref cells index))
                                (iota (* map-size map-size))))))

    (define (edge-strokes (cells (Vector Bool)) (cell Cell) (paint Paint) (lane F32))
      (→ (List Item))
      (filter-map
       (lambda (side) (edge-stroke cells cell (::first side) (::second side) paint lane))
       (list (Pair 1 0) (Pair -1 0) (Pair 0 1) (Pair 0 -1))))

    (define (edge-stroke (cells (Vector Bool))
                         (cell Cell)
                         (dx I64)
                         (dy I64)
                         (paint Paint)
                         (lane F32))
      (→ (Option Item))
      (let ((other (Cell (+ (::x cell) dx) (+ (::y cell) dy))))
        (if (and (in-bounds? other) (vector-ref cells (cell-index other)))
            (None)
            (Some (Item-glow-set (item (Tile)
                                       (Vec3 (+ (i64->f32 (::x cell))
                                                (+ (* 0.5 (i64->f32 dx)) (if (= dx 0) 0.0 lane)))
                                             0.075
                                             (+ (i64->f32 (::y cell))
                                                (+ (* 0.5 (i64->f32 dy)) (if (= dy 0) 0.0 lane))))
                                       (Vec3 (if (= dx 0) 1.06 0.06) 1.0 (if (= dy 0) 1.06 0.06))
                                       0.0
                                       (::color paint))
                                 0.8)))))

    ;; Cyan bounds what powered buildings see; brass bounds what powered
    ;; turrets can shoot.
    (define (coverage-items (world World)) (→ (List Item))
      (append (outline-items (::visible world) cyan 0.03)
              (outline-items (lit-cells (filter (lambda (node) (turret-node? world node))
                                                (::powered (::network world))))
                             brass
                             -0.03)))

    (define (turret-node? (world World) (node Node)) (→ Bool)
      (match (building world (::id node))
        ((Some b) (turret? b))
        ((None) #f)))

    (define (turret? (b Building)) (→ Bool)
      (match (::kind b)
        ((Turret) #t)
        (_ #f)))

    (define (structure-items (world World)) (→ (List Item))
      (concatenate
       (list (base-items) (place (hub-parts) (cell-point (::cell (::hub world)) 0.0) 0.0)
             (concatenate (map (lambda (b) (building-items world b)) (::buildings world)))
             (concatenate
              (map (lambda (c) (at-cell (::cell c) (crystal-parts))) (open-crystals world)))
             (nest-items world) (coverage-items world))))

    ;; ---- Energy ----

    ;; The node a powered node was reached from, toward the hub: each wire
    ;; runs from the node it was reached from.
    (define (parent (world World) (node Node)) (→ (Option Node))
      (match (find (lambda (wire) (= (::id (::to wire)) (::id node)))
                   (::wires (::network world)))
        ((Some wire) (Some (::from wire)))
        ((None) (None))))

    ;; Every wire energy crosses on its way from a working extractor to the
    ;; hub, as (from, toward) pairs.
    (define (flows (world World)) (→ (List (Pair Node Node)))
      (delete-duplicates (lambda (a b) (= (::id (::first a)) (::id (::first b))))
                         (concatenate (map (lambda (node) (route-home world node))
                                           (filter (lambda (node) (working-extractor? world node))
                                                   (::powered (::network world)))))))

    (define (route-home (world World) (node Node)) (→ (List (Pair Node Node)))
      (match (parent world node)
        ((Some up) (Cons (Pair node up) (route-home world up)))
        ((None) (Nil))))

    (define (working-extractor? (world World) (node Node)) (→ Bool)
      (match (building world (::id node))
        ((Some b) (and (match (::kind b) ((Extractor) #t) (_ #f))
                       (match (crystal-at world (::cell b))
                         ((Some c) (> (::reserve c) 0))
                         ((None) #f))))
        ((None) #f)))

    ;; Pulses two cells apart travel a quarter of a cell a tick. One that
    ;; reaches the end starts again from the beginning without travelling
    ;; back.
    (define (pulse-items (world World)) (→ (List Item))
      (concatenate (map (lambda (flow)
                          (flow-pulses (::tick world)
                                       (::cell (::first flow))
                                       (::cell (::second flow))))
                        (flows world))))

    (define (flow-pulses (tick I64) (from Cell) (to Cell)) (→ (List Item))
      (let* ((length (sqrt (i64->f32 (distance-squared from to))))
             (a (cell-point from (- wire-height 0.08)))
             (b (cell-point to (- wire-height 0.08))))
        (map (lambda (index)
               (let ((now (pulse-fraction tick index length))
                     (next (pulse-fraction (+ tick 1) index length)))
                 (Item-from-set (Item-glow-set (item (Octahedron)
                                                     (between a b next)
                                                     (Vec3 0.16 0.16 0.16)
                                                     0.0
                                                     (rgb 210 255 244))
                                               1.0)
                                (between a b (if (< next now) next now)))))
             (iota (max 1 (f32->i64 (/ length 2.0)))))))

    (define (pulse-fraction (tick I64) (index I64) (length F32)) (→ F32)
      (let ((travelled (+ (* 0.25 (i64->f32 tick)) (* 2.0 (i64->f32 index)))))
        (/ (- travelled (* length (floor (/ travelled length)))) length)))

    ;; ---- Enemies ----

    ;; Floating crystals: octahedral minions, tetrahedral raiders, boxy
    ;; burrowers and a great beast, crowned with more crystals as they rank.
    (define (enemy-parts (enemy Enemy)) (→ (List Item))
      (let* ((rank (::rank enemy))
             (size
              (match (::behavior enemy) ((Beast) 2.8) (_ (+ 0.85 (* 0.2 (i64->f32 rank))))))
             (mesh (cond ((::burrower enemy) (Box))
                         ((match (::behavior enemy) ((Raider) #t) (_ #f)) (Tetrahedron))
                         (else (Octahedron)))))
        (resize (append (list (part mesh
                                    (if (::burrower enemy) indigo gemstone)
                                    0.0
                                    0.0
                                    0.48
                                    0.62
                                    0.62
                                    0.62))
                        (append (if (< rank 2)
                                    (Nil)
                                    (list
                                     (part (Tetrahedron) gem-light -0.34 0.0 0.61 0.25 0.25 0.36)
                                     (part (Tetrahedron) gemstone 0.34 0.0 0.61 0.25 0.25 0.36)))
                                (if (< rank 4)
                                    (Nil)
                                    (list
                                     (part (Octahedron) gem-light 0.0 0.0 0.96 0.28 0.28 0.28)))))
                size size size)))

    ;; An enemy steps from its previous cell on multiples of its period; over
    ;; this tick it covers one period's share of the step.
    (define (enemy-span (world World) (enemy Enemy)) (→ (Pair Vec3 Vec3))
      (let* ((period (i64->f32 (enemy-period (::behavior enemy))))
             (phase (i64->f32 (remainder (+ (::tick world) (::id enemy))
                                         (enemy-period (::behavior enemy)))))
             (a (cell-point (::previous enemy) 0.0)) (b (cell-point (::cell enemy) 0.0)))
        (Pair (between a b (/ phase period)) (between a b (/ (+ phase 1.0) period)))))

    (define (enemy-items (world World) (enemy Enemy)) (→ (List Item))
      (let ((span (enemy-span world enemy)))
        (travel (enemy-parts enemy) (::first span) (::second span) 0.0)))

    (define (enemy-bar (yaw F32) (world World) (enemy Enemy)) (→ (List Item))
      (let ((span (enemy-span world enemy)))
        (bar-items yaw
                   (::first span)
                   (::second span)
                   1.0
                   (+ 0.9 (* 0.25 (i64->f32 (::rank enemy))))
                   (::health enemy)
                   (::maximum enemy)
                   health-paint)))

    ;; ---- Bars ----

    (define health-paint (Paint (rgb 118 249 143) 1.0))
    (define reserve-paint (Paint (rgb 214 151 255) 1.0))
    (define progress-paint (Paint (rgb 120 210 255) 1.0))

    ;; How a bar turns to face a camera at `angle`: its long side along the
    ;; screen, as an angle within one turn.
    (define (bar-yaw (angle F32)) (→ F32)
      (let ((turn (+ 0.7853982 angle)) (full 6.2831855))
        (- turn (* full (floor (/ turn full))))))

    ;; A dark frame `width` wide with a fill for `amount` of `capacity`,
    ;; `height` above a point moving from `from` to `to`, turned by `yaw` to
    ;; face the camera. A still bar moves from its cell to the same cell.
    (define (bar-items (yaw F32)
                       (from Vec3)
                       (to Vec3)
                       (width F32)
                       (height F32)
                       (amount I64)
                       (capacity I64)
                       (paint Paint))
      (→ (List Item))
      (let ((fill (* (* 0.9 width) (/ (i64->f32 (max 0 amount)) (i64->f32 (max 1 capacity))))))
        (travel (list (block (Paint (rgb 13 20 32) 1.0) 0.0 0.0 height width 0.03 0.18)
                      (block paint (- (/ fill 2.0) (* 0.45 width)) -0.02 height fill 0.03 0.1))
                from to yaw)))

    (define (still-bar (yaw F32)
                       (cell Cell)
                       (width F32)
                       (height F32)
                       (amount I64)
                       (capacity I64)
                       (paint Paint))
      (→ (List Item))
      (bar-items yaw
                 (cell-point cell 0.0)
                 (cell-point cell 0.0)
                 width
                 height
                 amount
                 capacity
                 paint))

    ;; Damaged buildings show their health, unfinished work its progress, and
    ;; mined crystals what they have left.
    (define (building-bars (yaw F32) (world World) (b Building)) (→ (List Item))
      (append (if (< (::health b) (kind-health (::kind b)))
                  (still-bar yaw
                             (::cell b)
                             1.0
                             1.2
                             (::health b)
                             (kind-health (::kind b))
                             health-paint)
                  (Nil))
              (match (::work b)
                ((Some work)
                 (still-bar yaw
                            (::cell b)
                            1.0
                            1.0
                            (::progress work)
                            (::duration work)
                            progress-paint))
                ((None) (Nil)))))

    (define (crystal-bars (yaw F32) (world World)) (→ (List Item))
      (concatenate (map (lambda (c)
                          (still-bar yaw
                                     (::cell c)
                                     1.0
                                     0.75
                                     (::reserve c)
                                     (* reserve-per-rate (::rate c))
                                     reserve-paint))
                        (filter (lambda (c)
                                  (match (building-at world (::cell c))
                                    ((Some _) #t)
                                    ((None) #f)))
                                (::crystals world)))))

    (define (hub-bars (yaw F32) (world World)) (→ (List Item))
      (let ((hub (::hub world)))
        (append (still-bar yaw (::cell hub) 1.0 1.25 (::health hub) hub-health health-paint)
                (match (::work hub)
                  ((Some work)
                   (still-bar yaw
                              (::cell hub)
                              1.0
                              1.05
                              (::progress work)
                              (::duration work)
                              progress-paint))
                  ((None) (Nil))))))

    ;; Each living nest that has been found shows its health in a wide bar
    ;; above its spire.
    (define (nest-bars (yaw F32) (world World)) (→ (List Item))
      (concatenate (map (lambda (nest)
                          (still-bar yaw
                                     (::cell nest)
                                     2.4
                                     3.2
                                     (::health nest)
                                     nest-health
                                     health-paint))
                        (filter (lambda (nest)
                                  (and (> (::health nest) 0) (explored? world (::cell nest))))
                                (::nests world)))))

    ;; ---- Combat ----

    ;; A turret's guns stay pointed where it last fired.
    (define (cannon-items (world World) (b Building)) (→ (List Item))
      (let ((cell (::cell b)))
        (match (::aim b)
          ((Some to) (place (cannon-parts (::level b)) (cell-point cell 0.0)
                            (atan2-f32 (negate (i64->f32 (- (::x to) (::x cell))))
                                       (negate (i64->f32 (- (::y to) (::y cell)))))))
          ((None) (at-cell cell (cannon-parts (::level b)))))))

    ;; A tracer crosses to its target over two ticks, then flashes.
    (define (shot-items (world World) (shot Shot)) (→ (List Item))
      (let ((age (- (::tick world) (::tick shot)))
            (from (cell-point (::from shot) 0.6))
            (to (cell-point (::to shot) 0.35)))
        (cond ((< age 2) (travel (list (block lamp 0.0 0.0 0.0 0.3 0.075 0.075))
                                 (between from to (/ (i64->f32 age) 2.0))
                                 (between from to (/ (i64->f32 (+ age 1)) 2.0))
                                 (atan2-f32 (negate (- (::z to) (::z from)))
                                            (- (::x to) (::x from)))))
              ((= age 2)
               (place
                (list (block lamp 0.0 0.0 0.0 0.4 0.07 0.07) (block lamp 0.0 0.0 0.0 0.07 0.4 0.07))
                to
                0.0))
              (else (Nil)))))

    ;; Smoke rises where the colony was struck in the last two seconds.
    (define (smoke-items (world World) (alert Alert)) (→ (List Item))
      (if (< (- (::tick world) (::tick alert)) 20)
          (concatenate
           (map (lambda (index) (puff (::tick world) (::cell alert) index)) (iota 4)))
          (Nil)))

    (define (puff (tick I64) (cell Cell) (index I64)) (→ (List Item))
      (let* ((phase (remainder (+ tick (* index 7)) 24)) (x (* (- (i64->f32 index) 1.5) 0.16))
             (rise (lambda (p) (cell-point cell (+ 0.3 (* (i64->f32 p) 0.055))))))
        (travel (list (block (if (= (remainder index 2) 0) cream steel) x 0.0 0.0 0.18 0.18 0.18))
                (rise phase) (rise (if (= phase 23) 0 (+ phase 1))) 0.0)))

    ;; Dust flies from rock being dug.
    (define (dig-items (world World) (dig Dig)) (→ (List Item))
      (let ((phase (* (i64->f32 (remainder (::tick world) 8)) 0.045)))
        (at-cell (::cell dig)
                 (list (block cream -0.35 0.1 (+ 0.4 phase) 0.22 0.22 0.22)
                       (block brass 0.2 -0.1 (- 0.8 phase) 0.16 0.16 0.16)
                       (block lamp 0.0 -0.2 0.12 0.45 0.08 0.08)))))

    (define (moving-items (world World)) (→ (List Item))
      (concatenate (list (concatenate (map (lambda (e) (enemy-items world e)) (seen-enemies world)))
                         (concatenate (map (lambda (b) (cannon-items world b))
                                           (filter (lambda (b) (and (built? b) (turret? b)))
                                                   (::buildings world))))
                         (concatenate (map (lambda (s) (shot-items world s)) (::shots world)))
                         (concatenate (map (lambda (a) (smoke-items world a)) (::alerts world)))
                         (concatenate (map (lambda (d) (dig-items world d))
                                           (filter (lambda (d) (explored? world (::cell d)))
                                                   (::digs world))))
                         (pulse-items world))))

    (define (seen-enemies (world World)) (→ (List Enemy))
      (filter (lambda (e) (visible? world (::cell e))) (::enemies world)))

    ;; Every bar, turned by `yaw` to face the camera.
    (define (bar-batch-items (world World) (yaw F32)) (→ (List Item))
      (concatenate
       (list (concatenate (map (lambda (e) (enemy-bar yaw world e)) (seen-enemies world)))
             (hub-bars yaw world)
             (crystal-bars yaw world)
             (concatenate (map (lambda (b) (building-bars yaw world b)) (::buildings world)))
             (nest-bars yaw world))))

    ;; ---- Cursor and previews ----

    ;; The hovered and selected cells glow in place of their ground, just
    ;; above water, which lies highest.
    (define (cursor-items (game Game)) (→ (List Item))
      (let ((glowing (lambda (option paint)
                       (match option
                         ((Some cell) (at-cell cell (list (flat paint 0.0 0.0 0.015 0.99 0.99))))
                         ((None) (Nil))))))
        (append
         (glowing (if (same-cell? (::hover game) (::selected game)) (None) (::hover game))
                  (Paint (rgb 214 250 190) 0.55))
         (glowing (::selected game) (Paint (rgb 255 236 140) 0.85)))))

    ;; The selection's glow covers the hover's on the same cell, rather than
    ;; fighting it at the same height.
    (define (same-cell? (a (Option Cell)) (b (Option Cell))) (→ Bool)
      (match a
        ((Some x) (match b ((Some y) (cell=? x y)) ((None) #f)))
        ((None) #f)))

    (define (cursor-version (game Game)) (→ I64)
      (+ (* (cell-code (::hover game)) 6401) (cell-code (::selected game))))

    (define (cell-code (option (Option Cell))) (→ I64)
      (match option
        ((Some cell) (+ 1 (cell-index cell)))
        ((None) 0)))

    ;; On the selected cell, a ghost of the building whose button the
    ;; pointer is over.
    (define (preview-items (game Game)) (→ (List Item))
      (match (::selected game)
        ((Some cell)
         (match (::preview game)
           ((Some kind) (at-cell cell (building-parts kind 1)))
           ((None) (Nil))))
        ((None) (Nil))))

    (define (preview-version (game Game)) (→ I64)
      (+ (* 4 (cell-code (::selected game)))
         (match (::preview game) ((Some kind) (+ 1 (kind-code kind))) ((None) 0))))

    (define (kind-code (kind Kind)) (→ I64)
      (match kind
        ((Extractor) 0)
        ((Pylon) 1)
        ((Turret) 2)))

    ;; ---- Light ----

    ;; The sun keeps its place relative to the camera, so every heading is
    ;; lit alike: from the left, above and behind the viewer.
    (define (camera-light (view Camera)) (→ Light)
      (let* ((eye (::eye view)) (target (::target view))
             (forward (unit (Vec3 (- (::x target) (::x eye))
                                  (- (::y target) (::y eye))
                                  (- (::z target) (::z eye)))))
             (right (unit (Vec3 (negate (::z forward)) 0.0 (::x forward))))
             (up (Vec3 (- (* (::y right) (::z forward)) (* (::z right) (::y forward)))
                       (- (* (::z right) (::x forward)) (* (::x right) (::z forward)))
                       (- (* (::x right) (::y forward))
                          (* (::y right) (::x forward))))))
        (Light (Vec3 (- (+ (* -0.5 (::x right)) (* 0.6 (::x up))) (::x forward))
                     (- (+ (* -0.5 (::y right)) (* 0.6 (::y up))) (::y forward))
                     (- (+ (* -0.5 (::z right)) (* 0.6 (::z up))) (::z forward)))
               0.65 0.5)))

    (define (unit (v Vec3)) (→ Vec3)
      (let ((length (sqrt (+ (* (::x v) (::x v))
                             (+ (* (::y v) (::y v)) (* (::z v) (::z v)))))))
        (Vec3 (/ (::x v) length) (/ (::y v) length) (/ (::z v) length))))

    ;; ---- Frames ----

    ;; A batch version: the game's epoch with a count that changes exactly
    ;; when the batch's items would, so a new game never reuses old items.
    (define (stamp (game Game) (count I64)) (→ I32)
      (i64->i32 (+ (* (remainder (::epoch game) 64) 16777216) (remainder count 16777216))))

    ;; Newly explored ground unveils from the middle outward over three
    ;; seconds; until then it is drawn apart from the rest.
    (define (unveiling? (world World)) (→ Bool)
      (< (- (::tick world) (::tick (::reveal world))) 30))

    (define (fresh? (world World) (index I64)) (→ Bool)
      (not (vector-ref (::before (::reveal world)) index)))

    (define (terrain-batches (game Game)) (→ (List Batch))
      (let* ((world (::world game)) (reveal (::reveal world)) (unveiling (unveiling? world))
             (progress (min 1.0
                            (/ (+ (i64->f32 (- (::tick world) (::tick reveal)))
                                  (world-motion game))
                               30.0))))
        (Cons
         (Batch 1 (stamp game (+ (* 2 (::structure-version world)) (if unveiling 0 1))) (Solid)
                (lambda ()
                  (terrain-items world
                                 (lambda (index) (or (not unveiling) (not (fresh? world index)))))))
         (if unveiling
             (list (Batch 2 (stamp game (::explored-version world))
                          (Revealed (cell-point (::center reveal) 0.0)
                                    (* (i64->f32 (::radius reveal))
                                       (* progress (- 2.0 progress))))
                          (lambda () (terrain-items world (lambda (index) (fresh? world index))))))
             (Nil)))))

    ;; Crystals shimmer, pulsing in strength.
    (define (shimmer-batch (game Game)) (→ Batch)
      (let* ((world (::world game)) (time (/ (i64->f32 (::shown game)) 1000.0)))
        (Batch 4 (stamp game (::structure-version world))
               (Translucent (+ 0.45 (* 0.25 (f64->f32 (sin (f32->f64 (* 2.5 time)))))))
               (lambda ()
                 (concatenate (map (lambda (c) (at-cell (::cell c) (shimmer-parts)))
                                   (open-crystals world)))))))

    ;; During the opening, the crystals in sight pulse white to show where
    ;; the first extractor goes.
    (define (beacon-batches (game Game)) (→ (List Batch))
      (let* ((world (::world game)) (time (/ (i64->f32 (::shown game)) 1000.0)))
        (if (opening? world)
            (list (Batch 10
                         (stamp game
                                (+ (::structure-version world) (::explored-version world)))
                         (Translucent (+ 0.5 (* 0.3 (f64->f32 (sin (f32->f64 (* 5.0 time)))))))
                         (lambda ()
                           (concatenate (map (lambda (c)
                                               (at-cell (::cell c)
                                                        (list (flat (Paint (rgb 255 255 255) 1.0)
                                                                    0.0
                                                                    0.0
                                                                    0.02
                                                                    0.99
                                                                    0.99))))
                                             (open-crystals world))))))
            (Nil))))

    ;; Bars follow the camera through every turn: their batch changes with
    ;; the eased heading, in steps too small to see. The tick and the
    ;; explored version only grow, so their sum changes whenever either
    ;; does, and a nest uncovered at the end shows its bar.
    (define (bar-batch (game Game)) (→ Batch)
      (let* ((world (::world game))
             (yaw (bar-yaw (heading-angle game)))
             (step (f32->i64 (round (* yaw 256.0)))))
        (Batch 8
               (stamp game (+ (* 2048 (+ (::tick world) (::explored-version world))) step))
               (Solid)
               (lambda () (bar-batch-items world yaw)))))

    (define (link-batch (game Game)) (→ Batch)
      (Batch 9
             (stamp game (::structure-version (::world game)))
             (Translucent 0.8)
             (lambda () (link-items (::world game)))))

    (define (cursor-batch (game Game)) (→ Batch)
      (Batch 6 (stamp game (cursor-version game)) (Solid) (lambda () (cursor-items game))))

    (define (preview-batch (game Game)) (→ Batch)
      (let ((time (/ (i64->f32 (::clock game)) 1000.0)))
        (Batch 7
               (stamp game (preview-version game))
               (Translucent (+ 0.45 (* 0.15 (f64->f32 (sin (f32->f64 (* 4.0 time)))))))
               (lambda () (preview-items game)))))

    (define (view-game (game Game)) (→ Frame)
      (let* ((world (::world game)) (camera (game-camera game)))
        (Frame camera (camera-light camera) sky (world-motion game)
               (concatenate (list (terrain-batches game)
                                  (list (Batch 3
                                               (stamp game (::structure-version world))
                                               (Solid)
                                               (lambda () (structure-items world)))
                                        (Batch 5
                                               (stamp game (::tick world))
                                               (Solid)
                                               (lambda () (moving-items world)))
                                        (bar-batch game) (link-batch game)
                                        (cursor-batch game) (shimmer-batch game))
                                  (beacon-batches game)
                                  (list (preview-batch game))))
               (Nil))))

    (define (filter-map (f (dyn (Fn A → (Option B)))) (items (List A))) (→ (List B)) (∀ A B)
      (fold-right
       (lambda (item kept) (match (f item) ((Some value) (Cons value kept)) ((None) kept)))
       (Nil)
       items))

    ))
