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

    (: sky I32)
    (define sky (rgb 28 151 223))

    ;; ---- Parts ----

    ;; A shape centered at (x, y, z) with z up and y north, and size w by d
    ;; by h, as an item standing in the host's coordinates.
    (: part (-> Mesh Paint F32 F32 F32 F32 F32 F32 Item))
    (define (part mesh paint x y z w d h)
      (Item-glow-set
       (item mesh (Vec3 x (- z (/ h 2.0)) (negate y)) (Vec3 w h d) 0.0 (Paint-color paint))
       (Paint-glow paint)))

    (: block (-> Paint F32 F32 F32 F32 F32 F32 Item))
    (define (block paint x y z w d h)
      (part (Box) paint x y z w d h))

    ;; A flat w by d square at height z.
    (: flat (-> Paint F32 F32 F32 F32 F32 Item))
    (define (flat paint x y z w d)
      (Item-glow-set (item (Tile) (Vec3 x z (negate y)) (Vec3 w 1.0 d) 0.0 (Paint-color paint))
                     (Paint-glow paint)))

    ;; Scales the positions and sizes of standing parts.
    (: resize (-> (List Item) F32 F32 F32 (List Item)))
    (define (resize parts kx ky kz)
      (map (lambda (it)
             (let* ((p (Item-position it))
                    (s (Item-scale it))
                    (moved (Vec3 (* kx (Vec3-x p)) (* ky (Vec3-y p)) (* kz (Vec3-z p)))))
               (Item-from-set (Item-scale-set (Item-position-set it moved)
                                              (Vec3 (* kx (Vec3-x s))
                                                    (* ky (Vec3-y s))
                                                    (* kz (Vec3-z s))))
                              moved)))
           parts))

    ;; Turns parts by `yaw` about their origin and moves them to `origin`.
    (: place (-> (List Item) Vec3 F32 (List Item)))
    (define (place parts origin yaw)
      (map (lambda (it)
             (Item-yaw-set
              (Item-from-set (Item-position-set it (turned (Item-position it) origin yaw))
                             (turned (Item-from it) origin yaw))
              (+ yaw (Item-yaw it))))
           parts))

    (: turned (-> Vec3 Vec3 F32 Vec3))
    (define (turned p origin yaw)
      (let ((c (f64->f32 (cos (f32->f64 yaw)))) (s (f64->f32 (sin (f32->f64 yaw)))))
        (Vec3 (+ (Vec3-x origin) (+ (* c (Vec3-x p)) (* s (Vec3-z p))))
              (+ (Vec3-y origin) (Vec3-y p))
              (+ (Vec3-z origin) (- (* c (Vec3-z p)) (* s (Vec3-x p)))))))

    ;; Parts that move from one place to another over the coming tick.
    (: travel (-> (List Item) Vec3 Vec3 F32 (List Item)))
    (define (travel parts from to yaw)
      (map (lambda (pair) (Item-from-set (Pair-second pair) (Item-position (Pair-first pair))))
           (zip (place parts from yaw) (place parts to yaw))))

    (: cell-point (-> Cell F32 Vec3))
    (define (cell-point cell height)
      (Vec3 (i64->f32 (Cell-x cell)) height (i64->f32 (Cell-y cell))))

    (: at-cell (-> Cell (List Item) (List Item)))
    (define (at-cell cell parts)
      (place parts (cell-point cell 0.0) 0.0))

    (: between (-> Vec3 Vec3 F32 Vec3))
    (define (between a b t)
      (Vec3 (+ (Vec3-x a) (* t (- (Vec3-x b) (Vec3-x a))))
            (+ (Vec3-y a) (* t (- (Vec3-y b) (Vec3-y a))))
            (+ (Vec3-z a) (* t (- (Vec3-z b) (Vec3-z a))))))

    (: atan2-f32 (-> F32 F32 F32))
    (define (atan2-f32 y x)
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

    (: tileset (-> Biome Tileset))
    (define (tileset biome)
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
    (: open-paint (-> World Tileset Cell Paint))
    (define (open-paint world tiles cell)
      (Paint (if (visible? world cell)
                 (match (Tileset-shore tiles)
                   ((Some shore) (if (beside-water? world cell) shore (open-tone tiles cell)))
                   ((None) (open-tone tiles cell)))
                 (Tileset-unseen tiles))
             0.0))

    (: open-tone (-> Tileset Cell I32))
    (define (open-tone tiles cell)
      (let ((x (Cell-x cell)) (y (Cell-y cell)))
        (cond ((= (remainder (+ (* x 13) (* y 7)) 5) 0) (Tileset-light tiles))
              ((= (remainder (+ x (* y 3)) 3) 0) (Tileset-deep tiles))
              (else (Tileset-middle tiles)))))

    ;; Unexplored water does not count, so a shore never gives it away.
    (: beside-water? (-> World Cell Bool))
    (define (beside-water? world cell)
      (any? (lambda (n)
              (and (explored? world n)
                   (match (ground-at (World-land world) n) ((Water) #t) (_ #f))))
            (neighbors cell)))

    ;; Rock is a grey peak in meadows and on islands, a flat-topped mesa in
    ;; the desert, and a snow-capped peak in the tundra. Dug rock is a floor.
    (: ground-parts (-> World Cell (List Item)))
    (define (ground-parts world cell)
      (let* ((biome (Land-biome (World-land world)))
             (tiles (tileset biome))
             (floor (flat (open-paint world tiles cell) 0.0 0.0 0.0 0.99 0.99)))
        (match (ground-at (World-land world) cell)
          ((Open) (list floor))
          ((Water) (list (flat (Paint (Tileset-water tiles) 0.1) 0.0 0.0 0.012 0.99 0.99)))
          ((Ice) (list (flat (Paint (Tileset-ice tiles) 0.2) 0.0 0.0 0.008 0.99 0.99)))
          ((Rock) (if (opened? world cell)
                      (list (flat (Paint (Tileset-dug tiles) 0.0) 0.0 0.0 0.0 0.99 0.99))
                      (Cons floor (rock-parts biome (Paint (Tileset-rock tiles) 0.0))))))))

    (: rock-parts (-> Biome Paint (List Item)))
    (define (rock-parts biome paint)
      (match biome
        ((Desert) (list (block paint 0.0 0.0 0.3 0.98 0.98 0.6)))
        ((Tundra)
         (list (part (Pyramid) paint 0.0 0.0 0.425 1.0 0.94 0.85)
               (part (Pyramid) (Paint (rgb 250 252 255) 0.1) 0.0 0.0 0.7 0.42 0.4 0.3)))
        (_ (list (part (Pyramid) paint 0.0 0.0 0.425 1.0 0.94 0.85)))))

    ;; The world's base beneath the map, with a cream rim.
    (: base-items (-> (List Item)))
    (define (base-items)
      (let* ((size (i64->f32 map-size)) (middle (- (/ size 2.0) 0.5)))
        (list (Item-glow-set
               (item (Box) (Vec3 middle -0.7 middle) (Vec3 size 0.69 size) 0.0 (rgb 31 96 119))
               0.7)
              (block cream -0.5 (negate middle) 0.02 0.12 size 0.06)
              (block cream (- size 0.5) (negate middle) 0.02 0.12 size 0.06)
              (block cream middle 0.5 0.02 size 0.12 0.06)
              (block cream middle (- 0.5 size) 0.02 size 0.12 0.06))))

    ;; Explored cells that `include?` picks.
    (: terrain-items (-> World (-> I64 Bool) (List Item)))
    (define (terrain-items world include?)
      (concatenate
       (map (lambda (index) (at-cell (index-cell index) (ground-parts world (index-cell index))))
            (filter
             (lambda (index) (and (vector-ref (World-explored world) index) (include? index)))
             (iota (* map-size map-size))))))

    ;; ---- Buildings ----

    ;; The hub's low roof leaves the wires' junction showing at their height.
    (: hub-parts (-> (List Item)))
    (define (hub-parts)
      (resize (list (block steel 0.0 0.0 0.12 3.0 3.0 0.24) (block cream 0.0 0.0 0.51 2.6 2.6 0.78)
                    (block brass -0.93 0.0 0.96 1.04 2.9 0.12)
                    (block brass 0.93 0.0 0.96 1.04 2.9 0.12)
                    (block brass 0.0 -0.93 0.96 0.82 1.04 0.12)
                    (block brass 0.0 0.93 0.96 0.82 1.04 0.12)
                    (block steel 0.0 0.0 1.08 0.18 0.18 0.36)
                    (block cyan 0.0 0.0 1.3846 0.34 0.34 0.12)
                    (block cyan 0.0 -1.31 0.55 1.5 0.04 0.32))
              1.0 0.65 1.0))

    (: extractor-parts (-> I64 (List Item)))
    (define (extractor-parts level)
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

    (: pylon-parts (-> I64 (List Item)))
    (define (pylon-parts level)
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
    (: turret-parts (-> I64 (List Item)))
    (define (turret-parts level)
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
    (: cannon-parts (-> I64 (List Item)))
    (define (cannon-parts level)
      (concatenate (map (lambda (index)
                          (place (resize (list (block rust 0.0 -0.1 0.0 0.58 0.5 0.32)
                                               (block cream 0.0 0.35 0.09 0.22 0.72 0.22)
                                               (block steel 0.0 0.75 0.09 0.15 0.42 0.15)
                                               (block brass 0.0 0.97 0.09 0.27 0.12 0.27))
                                         1.0 0.55 1.0)
                                 (Vec3 0.0 (+ 0.3 (* 0.22 (i64->f32 index))) 0.0) 0.0))
                        (iota level))))

    (: construction-parts (-> (List Item)))
    (define (construction-parts)
      (list (block steel 0.0 0.0 0.06 0.9 0.9 0.12) (block brass 0.0 0.0 0.22 0.43 0.43 0.32)
            (block lamp -0.4 -0.4 0.18 0.07 0.07 0.36) (block lamp 0.4 0.4 0.18 0.07 0.07 0.36)))

    (: building-parts (-> Kind I64 (List Item)))
    (define (building-parts kind level)
      (if (= level 0)
          (construction-parts)
          (match kind
            ((Extractor) (extractor-parts level))
            ((Pylon) (pylon-parts level))
            ((Turret) (turret-parts level)))))

    ;; An unpowered building loses its color and glow.
    (: unpowered (-> (List Item) (List Item)))
    (define (unpowered parts)
      (map (lambda (it) (Item-glow-set (Item-color-set it (Paint-color shadow)) 0.0)) parts))

    (: building-items (-> World Building (List Item)))
    (define (building-items world building)
      (let ((parts (building-parts (Building-kind building) (Building-level building))))
        (at-cell (Building-cell building)
                 (if (or (not (built? building)) (powered? world (Building-id building)))
                     parts
                     (unpowered parts)))))

    ;; ---- Crystals and nests ----

    (: crystal-parts (-> (List Item)))
    (define (crystal-parts)
      (list (part (Tetrahedron) gemstone -0.16 -0.04 0.217 0.62 0.62 0.686)
            (part (Tetrahedron) gem-light 0.23 0.16 0.178 0.44 0.44 0.564)
            (part (Tetrahedron) indigo 0.12 -0.28 0.124 0.32 0.32 0.392)))

    (: shimmer-parts (-> (List Item)))
    (define (shimmer-parts)
      (list (flat gemstone 0.0 0.0 0.025 1.1 1.1)
            (part (Octahedron) (Paint (rgb 232 208 255) 0.9) -0.16 -0.04 0.58 0.08 0.08 0.2)
            (part (Octahedron) gem-light 0.23 0.16 0.48 0.06 0.06 0.14)))

    ;; Crystals in explored ground with energy left, not under a building or
    ;; a living nest.
    (: open-crystals (-> World (List Crystal)))
    (define (open-crystals world)
      (filter (lambda (c) (let ((cell (Crystal-cell c)))
                            (and (explored? world cell) (> (Crystal-reserve c) 0)
                                 (match (building-at world cell) ((Some _) #f) ((None) #t))
                                 (match (nest-at world cell)
                                   ((Some nest) (= (Nest-health nest) 0))
                                   ((None) #t)))))
              (World-crystals world)))

    (: nest-parts (-> (List Item)))
    (define (nest-parts)
      (list (block steel 0.0 0.0 0.2 2.8 2.8 0.4) (part (Pyramid) violet 0.0 0.0 1.1 2.5 2.5 2.0)
            (part (Pyramid) cream -1.0 -1.0 1.4 0.55 0.55 2.8)
            (part (Pyramid) cream 1.0 1.0 1.4 0.55 0.55 2.8)
            (block warning 0.0 -1.24 0.6 1.1 0.08 0.7)))

    (: nest-items (-> World (List Item)))
    (define (nest-items world)
      (concatenate (map (lambda (nest) (at-cell (Nest-cell nest) (nest-parts)))
                        (filter (lambda (nest)
                                  (and (> (Nest-health nest) 0) (explored? world (Nest-cell nest))))
                                (World-nests world)))))

    ;; ---- Wires and outlines ----

    (: wire-height F32)
    (define wire-height 0.9)

    ;; A thin beam at wire height from one cell to another.
    (: beam (-> Cell Cell F32 Paint Item))
    (define (beam from to thickness paint)
      (let* ((a (cell-point from (- wire-height (/ thickness 2.0))))
             (b (cell-point to (- wire-height (/ thickness 2.0))))
             (dx (- (Vec3-x b) (Vec3-x a))) (dz (- (Vec3-z b) (Vec3-z a))))
        (Item-glow-set (item (Box)
                             (between a b 0.5)
                             (Vec3 (sqrt (+ (* dx dx) (* dz dz))) thickness thickness)
                             (atan2-f32 (negate dz) dx)
                             (Paint-color paint))
                       (Paint-glow paint))))

    ;; Wires are thin glassy turquoise beams between powered buildings, and
    ;; grey among unpowered ones.
    (: link-items (-> World (List Item)))
    (define (link-items world)
      (map (lambda (wire)
             (beam (Node-cell (Wire-from wire)) (Node-cell (Wire-to wire)) 0.07
                   (if (powered? world (Node-id (Wire-from wire)))
                       (Paint (rgb 35 242 195) 0.7)
                       (Paint (rgb 120 128 140) 0.2))))
           (Network-wires (World-network world))))

    ;; Thin strokes along the edges of a set of cells, shifted by `lane` so
    ;; two outlines on one edge lie side by side.
    (: outline-items (-> (Vector Bool) Paint F32 (List Item)))
    (define (outline-items cells paint lane)
      (concatenate (map (lambda (index) (edge-strokes cells (index-cell index) paint lane))
                        (filter (lambda (index) (vector-ref cells index))
                                (iota (* map-size map-size))))))

    (: edge-strokes (-> (Vector Bool) Cell Paint F32 (List Item)))
    (define (edge-strokes cells cell paint lane)
      (filter-map
       (lambda (side) (edge-stroke cells cell (Pair-first side) (Pair-second side) paint lane))
       (list (Pair 1 0) (Pair -1 0) (Pair 0 1) (Pair 0 -1))))

    (: edge-stroke (-> (Vector Bool) Cell I64 I64 Paint F32 (Option Item)))
    (define (edge-stroke cells cell dx dy paint lane)
      (let ((other (Cell (+ (Cell-x cell) dx) (+ (Cell-y cell) dy))))
        (if (and (in-bounds? other) (vector-ref cells (cell-index other)))
            (None)
            (Some (Item-glow-set (item (Tile)
                                       (Vec3 (+ (i64->f32 (Cell-x cell))
                                                (+ (* 0.5 (i64->f32 dx)) (if (= dx 0) 0.0 lane)))
                                             0.075
                                             (+ (i64->f32 (Cell-y cell))
                                                (+ (* 0.5 (i64->f32 dy)) (if (= dy 0) 0.0 lane))))
                                       (Vec3 (if (= dx 0) 1.06 0.06) 1.0 (if (= dy 0) 1.06 0.06))
                                       0.0
                                       (Paint-color paint))
                                 0.8)))))

    ;; Cyan bounds what powered buildings see; brass bounds what powered
    ;; turrets can shoot.
    (: coverage-items (-> World (List Item)))
    (define (coverage-items world)
      (append (outline-items (World-visible world) cyan 0.03)
              (outline-items (lit-cells (filter (lambda (node) (turret-node? world node))
                                                (Network-powered (World-network world))))
                             brass
                             -0.03)))

    (: turret-node? (-> World Node Bool))
    (define (turret-node? world node)
      (match (building world (Node-id node))
        ((Some b) (turret? b))
        ((None) #f)))

    (: turret? (-> Building Bool))
    (define (turret? b)
      (match (Building-kind b)
        ((Turret) #t)
        (_ #f)))

    (: structure-items (-> World (List Item)))
    (define (structure-items world)
      (concatenate
       (list (base-items) (place (hub-parts) (cell-point (Hub-cell (World-hub world)) 0.0) 0.0)
             (concatenate (map (lambda (b) (building-items world b)) (World-buildings world)))
             (concatenate
              (map (lambda (c) (at-cell (Crystal-cell c) (crystal-parts))) (open-crystals world)))
             (nest-items world) (coverage-items world))))

    ;; ---- Energy ----

    ;; The node a powered node was reached from, toward the hub: each wire
    ;; runs from the node it was reached from.
    (: parent (-> World Node (Option Node)))
    (define (parent world node)
      (match (find (lambda (wire) (= (Node-id (Wire-to wire)) (Node-id node)))
                   (Network-wires (World-network world)))
        ((Some wire) (Some (Wire-from wire)))
        ((None) (None))))

    ;; Every wire energy crosses on its way from a working extractor to the
    ;; hub, as (from, toward) pairs.
    (: flows (-> World (List (Pair Node Node))))
    (define (flows world)
      (delete-duplicates (lambda (a b) (= (Node-id (Pair-first a)) (Node-id (Pair-first b))))
                         (concatenate (map (lambda (node) (route-home world node))
                                           (filter (lambda (node) (working-extractor? world node))
                                                   (Network-powered (World-network world)))))))

    (: route-home (-> World Node (List (Pair Node Node))))
    (define (route-home world node)
      (match (parent world node)
        ((Some up) (Cons (Pair node up) (route-home world up)))
        ((None) (Nil))))

    (: working-extractor? (-> World Node Bool))
    (define (working-extractor? world node)
      (match (building world (Node-id node))
        ((Some b) (and (match (Building-kind b) ((Extractor) #t) (_ #f))
                       (match (crystal-at world (Building-cell b))
                         ((Some c) (> (Crystal-reserve c) 0))
                         ((None) #f))))
        ((None) #f)))

    ;; Pulses two cells apart travel a quarter of a cell a tick. One that
    ;; reaches the end starts again from the beginning without travelling
    ;; back.
    (: pulse-items (-> World (List Item)))
    (define (pulse-items world)
      (concatenate (map (lambda (flow)
                          (flow-pulses (World-tick world)
                                       (Node-cell (Pair-first flow))
                                       (Node-cell (Pair-second flow))))
                        (flows world))))

    (: flow-pulses (-> I64 Cell Cell (List Item)))
    (define (flow-pulses tick from to)
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

    (: pulse-fraction (-> I64 I64 F32 F32))
    (define (pulse-fraction tick index length)
      (let ((travelled (+ (* 0.25 (i64->f32 tick)) (* 2.0 (i64->f32 index)))))
        (/ (- travelled (* length (floor (/ travelled length)))) length)))

    ;; ---- Enemies ----

    ;; Floating crystals: octahedral minions, tetrahedral raiders, boxy
    ;; burrowers and a great beast, crowned with more crystals as they rank.
    (: enemy-parts (-> Enemy (List Item)))
    (define (enemy-parts enemy)
      (let* ((rank (Enemy-rank enemy))
             (size
              (match (Enemy-behavior enemy) ((Beast) 2.8) (_ (+ 0.85 (* 0.2 (i64->f32 rank))))))
             (mesh (cond ((Enemy-burrower enemy) (Box))
                         ((match (Enemy-behavior enemy) ((Raider) #t) (_ #f)) (Tetrahedron))
                         (else (Octahedron)))))
        (resize (append (list (part mesh
                                    (if (Enemy-burrower enemy) indigo gemstone)
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
    (: enemy-span (-> World Enemy (Pair Vec3 Vec3)))
    (define (enemy-span world enemy)
      (let* ((period (i64->f32 (enemy-period (Enemy-behavior enemy))))
             (phase (i64->f32 (remainder (+ (World-tick world) (Enemy-id enemy))
                                         (enemy-period (Enemy-behavior enemy)))))
             (a (cell-point (Enemy-previous enemy) 0.0)) (b (cell-point (Enemy-cell enemy) 0.0)))
        (Pair (between a b (/ phase period)) (between a b (/ (+ phase 1.0) period)))))

    (: enemy-items (-> World Enemy (List Item)))
    (define (enemy-items world enemy)
      (let ((span (enemy-span world enemy)))
        (travel (enemy-parts enemy) (Pair-first span) (Pair-second span) 0.0)))

    (: enemy-bar (-> F32 World Enemy (List Item)))
    (define (enemy-bar yaw world enemy)
      (let ((span (enemy-span world enemy)))
        (bar-items yaw
                   (Pair-first span)
                   (Pair-second span)
                   1.0
                   (+ 0.9 (* 0.25 (i64->f32 (Enemy-rank enemy))))
                   (Enemy-health enemy)
                   (Enemy-maximum enemy)
                   health-paint)))

    ;; ---- Bars ----

    (define health-paint (Paint (rgb 118 249 143) 1.0))
    (define reserve-paint (Paint (rgb 214 151 255) 1.0))
    (define progress-paint (Paint (rgb 120 210 255) 1.0))

    ;; How a bar turns to face a camera at `angle`: its long side along the
    ;; screen, as an angle within one turn.
    (: bar-yaw (-> F32 F32))
    (define (bar-yaw angle)
      (let ((turn (+ 0.7853982 angle)) (full 6.2831855))
        (- turn (* full (floor (/ turn full))))))

    ;; A dark frame `width` wide with a fill for `amount` of `capacity`,
    ;; `height` above a point moving from `from` to `to`, turned by `yaw` to
    ;; face the camera. A still bar moves from its cell to the same cell.
    (: bar-items (-> F32 Vec3 Vec3 F32 F32 I64 I64 Paint (List Item)))
    (define (bar-items yaw from to width height amount capacity paint)
      (let ((fill (* (* 0.9 width) (/ (i64->f32 (max 0 amount)) (i64->f32 (max 1 capacity))))))
        (travel (list (block (Paint (rgb 13 20 32) 1.0) 0.0 0.0 height width 0.03 0.18)
                      (block paint (- (/ fill 2.0) (* 0.45 width)) -0.02 height fill 0.03 0.1))
                from to yaw)))

    (: still-bar (-> F32 Cell F32 F32 I64 I64 Paint (List Item)))
    (define (still-bar yaw cell width height amount capacity paint)
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
    (: building-bars (-> F32 World Building (List Item)))
    (define (building-bars yaw world b)
      (append (if (< (Building-health b) (kind-health (Building-kind b)))
                  (still-bar yaw
                             (Building-cell b)
                             1.0
                             1.2
                             (Building-health b)
                             (kind-health (Building-kind b))
                             health-paint)
                  (Nil))
              (match (Building-work b)
                ((Some work)
                 (still-bar yaw
                            (Building-cell b)
                            1.0
                            1.0
                            (Work-progress work)
                            (Work-duration work)
                            progress-paint))
                ((None) (Nil)))))

    (: crystal-bars (-> F32 World (List Item)))
    (define (crystal-bars yaw world)
      (concatenate (map (lambda (c)
                          (still-bar yaw
                                     (Crystal-cell c)
                                     1.0
                                     0.75
                                     (Crystal-reserve c)
                                     (* reserve-per-rate (Crystal-rate c))
                                     reserve-paint))
                        (filter (lambda (c)
                                  (match (building-at world (Crystal-cell c))
                                    ((Some _) #t)
                                    ((None) #f)))
                                (World-crystals world)))))

    (: hub-bars (-> F32 World (List Item)))
    (define (hub-bars yaw world)
      (let ((hub (World-hub world)))
        (append (still-bar yaw (Hub-cell hub) 1.0 1.25 (Hub-health hub) hub-health health-paint)
                (match (Hub-work hub)
                  ((Some work)
                   (still-bar yaw
                              (Hub-cell hub)
                              1.0
                              1.05
                              (Work-progress work)
                              (Work-duration work)
                              progress-paint))
                  ((None) (Nil))))))

    ;; Each living nest that has been found shows its health in a wide bar
    ;; above its spire.
    (: nest-bars (-> F32 World (List Item)))
    (define (nest-bars yaw world)
      (concatenate (map (lambda (nest)
                          (still-bar yaw
                                     (Nest-cell nest)
                                     2.4
                                     3.2
                                     (Nest-health nest)
                                     nest-health
                                     health-paint))
                        (filter (lambda (nest)
                                  (and (> (Nest-health nest) 0) (explored? world (Nest-cell nest))))
                                (World-nests world)))))

    ;; ---- Combat ----

    ;; A turret's guns stay pointed where it last fired.
    (: cannon-items (-> World Building (List Item)))
    (define (cannon-items world b)
      (let ((cell (Building-cell b)))
        (match (Building-aim b)
          ((Some to) (place (cannon-parts (Building-level b)) (cell-point cell 0.0)
                            (atan2-f32 (negate (i64->f32 (- (Cell-x to) (Cell-x cell))))
                                       (negate (i64->f32 (- (Cell-y to) (Cell-y cell)))))))
          ((None) (at-cell cell (cannon-parts (Building-level b)))))))

    ;; A tracer crosses to its target over two ticks, then flashes.
    (: shot-items (-> World Shot (List Item)))
    (define (shot-items world shot)
      (let ((age (- (World-tick world) (Shot-tick shot)))
            (from (cell-point (Shot-from shot) 0.6))
            (to (cell-point (Shot-to shot) 0.35)))
        (cond ((< age 2) (travel (list (block lamp 0.0 0.0 0.0 0.3 0.075 0.075))
                                 (between from to (/ (i64->f32 age) 2.0))
                                 (between from to (/ (i64->f32 (+ age 1)) 2.0))
                                 (atan2-f32 (negate (- (Vec3-z to) (Vec3-z from)))
                                            (- (Vec3-x to) (Vec3-x from)))))
              ((= age 2)
               (place
                (list (block lamp 0.0 0.0 0.0 0.4 0.07 0.07) (block lamp 0.0 0.0 0.0 0.07 0.4 0.07))
                to
                0.0))
              (else (Nil)))))

    ;; Smoke rises where the colony was struck in the last two seconds.
    (: smoke-items (-> World Alert (List Item)))
    (define (smoke-items world alert)
      (if (< (- (World-tick world) (Alert-tick alert)) 20)
          (concatenate
           (map (lambda (index) (puff (World-tick world) (Alert-cell alert) index)) (iota 4)))
          (Nil)))

    (: puff (-> I64 Cell I64 (List Item)))
    (define (puff tick cell index)
      (let* ((phase (remainder (+ tick (* index 7)) 24)) (x (* (- (i64->f32 index) 1.5) 0.16))
             (rise (lambda (p) (cell-point cell (+ 0.3 (* (i64->f32 p) 0.055))))))
        (travel (list (block (if (= (remainder index 2) 0) cream steel) x 0.0 0.0 0.18 0.18 0.18))
                (rise phase) (rise (if (= phase 23) 0 (+ phase 1))) 0.0)))

    ;; Dust flies from rock being dug.
    (: dig-items (-> World Dig (List Item)))
    (define (dig-items world dig)
      (let ((phase (* (i64->f32 (remainder (World-tick world) 8)) 0.045)))
        (at-cell (Dig-cell dig)
                 (list (block cream -0.35 0.1 (+ 0.4 phase) 0.22 0.22 0.22)
                       (block brass 0.2 -0.1 (- 0.8 phase) 0.16 0.16 0.16)
                       (block lamp 0.0 -0.2 0.12 0.45 0.08 0.08)))))

    (: moving-items (-> World (List Item)))
    (define (moving-items world)
      (concatenate (list (concatenate (map (lambda (e) (enemy-items world e)) (seen-enemies world)))
                         (concatenate (map (lambda (b) (cannon-items world b))
                                           (filter (lambda (b) (and (built? b) (turret? b)))
                                                   (World-buildings world))))
                         (concatenate (map (lambda (s) (shot-items world s)) (World-shots world)))
                         (concatenate (map (lambda (a) (smoke-items world a)) (World-alerts world)))
                         (concatenate (map (lambda (d) (dig-items world d))
                                           (filter (lambda (d) (explored? world (Dig-cell d)))
                                                   (World-digs world))))
                         (pulse-items world))))

    (: seen-enemies (-> World (List Enemy)))
    (define (seen-enemies world)
      (filter (lambda (e) (visible? world (Enemy-cell e))) (World-enemies world)))

    ;; Every bar, turned by `yaw` to face the camera.
    (: bar-batch-items (-> World F32 (List Item)))
    (define (bar-batch-items world yaw)
      (concatenate
       (list (concatenate (map (lambda (e) (enemy-bar yaw world e)) (seen-enemies world)))
             (hub-bars yaw world)
             (crystal-bars yaw world)
             (concatenate (map (lambda (b) (building-bars yaw world b)) (World-buildings world)))
             (nest-bars yaw world))))

    ;; ---- Cursor and previews ----

    ;; The hovered and selected cells glow in place of their ground, just
    ;; above water, which lies highest.
    (: cursor-items (-> Game (List Item)))
    (define (cursor-items game)
      (let ((glowing (lambda (option paint)
                       (match option
                         ((Some cell) (at-cell cell (list (flat paint 0.0 0.0 0.015 0.99 0.99))))
                         ((None) (Nil))))))
        (append
         (glowing (if (same-cell? (Game-hover game) (Game-selected game)) (None) (Game-hover game))
                  (Paint (rgb 214 250 190) 0.55))
         (glowing (Game-selected game) (Paint (rgb 255 236 140) 0.85)))))

    ;; The selection's glow covers the hover's on the same cell, rather than
    ;; fighting it at the same height.
    (: same-cell? (-> (Option Cell) (Option Cell) Bool))
    (define (same-cell? a b)
      (match a
        ((Some x) (match b ((Some y) (cell=? x y)) ((None) #f)))
        ((None) #f)))

    (: cursor-version (-> Game I64))
    (define (cursor-version game)
      (+ (* (cell-code (Game-hover game)) 6401) (cell-code (Game-selected game))))

    (: cell-code (-> (Option Cell) I64))
    (define (cell-code option)
      (match option
        ((Some cell) (+ 1 (cell-index cell)))
        ((None) 0)))

    ;; On the selected cell, a ghost of the building whose button the
    ;; pointer is over.
    (: preview-items (-> Game (List Item)))
    (define (preview-items game)
      (match (Game-selected game)
        ((Some cell)
         (match (Game-preview game)
           ((Some kind) (at-cell cell (building-parts kind 1)))
           ((None) (Nil))))
        ((None) (Nil))))

    (: preview-version (-> Game I64))
    (define (preview-version game)
      (+ (* 4 (cell-code (Game-selected game)))
         (match (Game-preview game) ((Some kind) (+ 1 (kind-code kind))) ((None) 0))))

    (: kind-code (-> Kind I64))
    (define (kind-code kind)
      (match kind
        ((Extractor) 0)
        ((Pylon) 1)
        ((Turret) 2)))

    ;; ---- Light ----

    ;; The sun keeps its place relative to the camera, so every heading is
    ;; lit alike: from the left, above and behind the viewer.
    (: camera-light (-> Camera Light))
    (define (camera-light view)
      (let* ((eye (Camera-eye view)) (target (Camera-target view))
             (forward (unit (Vec3 (- (Vec3-x target) (Vec3-x eye))
                                  (- (Vec3-y target) (Vec3-y eye))
                                  (- (Vec3-z target) (Vec3-z eye)))))
             (right (unit (Vec3 (negate (Vec3-z forward)) 0.0 (Vec3-x forward))))
             (up (Vec3 (- (* (Vec3-y right) (Vec3-z forward)) (* (Vec3-z right) (Vec3-y forward)))
                       (- (* (Vec3-z right) (Vec3-x forward)) (* (Vec3-x right) (Vec3-z forward)))
                       (- (* (Vec3-x right) (Vec3-y forward))
                          (* (Vec3-y right) (Vec3-x forward))))))
        (Light (Vec3 (- (+ (* -0.5 (Vec3-x right)) (* 0.6 (Vec3-x up))) (Vec3-x forward))
                     (- (+ (* -0.5 (Vec3-y right)) (* 0.6 (Vec3-y up))) (Vec3-y forward))
                     (- (+ (* -0.5 (Vec3-z right)) (* 0.6 (Vec3-z up))) (Vec3-z forward)))
               0.65 0.5)))

    (: unit (-> Vec3 Vec3))
    (define (unit v)
      (let ((length (sqrt (+ (* (Vec3-x v) (Vec3-x v))
                             (+ (* (Vec3-y v) (Vec3-y v)) (* (Vec3-z v) (Vec3-z v)))))))
        (Vec3 (/ (Vec3-x v) length) (/ (Vec3-y v) length) (/ (Vec3-z v) length))))

    ;; ---- Frames ----

    ;; A batch version: the game's epoch with a count that changes exactly
    ;; when the batch's items would, so a new game never reuses old items.
    (: stamp (-> Game I64 I32))
    (define (stamp game count)
      (i64->i32 (+ (* (remainder (Game-epoch game) 64) 16777216) (remainder count 16777216))))

    ;; Newly explored ground unveils from the middle outward over three
    ;; seconds; until then it is drawn apart from the rest.
    (: unveiling? (-> World Bool))
    (define (unveiling? world)
      (< (- (World-tick world) (Reveal-tick (World-reveal world))) 30))

    (: fresh? (-> World I64 Bool))
    (define (fresh? world index)
      (not (vector-ref (Reveal-before (World-reveal world)) index)))

    (: terrain-batches (-> Game (List Batch)))
    (define (terrain-batches game)
      (let* ((world (Game-world game)) (reveal (World-reveal world)) (unveiling (unveiling? world))
             (progress (min 1.0
                            (/ (+ (i64->f32 (- (World-tick world) (Reveal-tick reveal)))
                                  (world-motion game))
                               30.0))))
        (Cons
         (Batch 1 (stamp game (+ (* 2 (World-structure-version world)) (if unveiling 0 1))) (Solid)
                (lambda ()
                  (terrain-items world
                                 (lambda (index) (or (not unveiling) (not (fresh? world index)))))))
         (if unveiling
             (list (Batch 2 (stamp game (World-explored-version world))
                          (Revealed (cell-point (Reveal-center reveal) 0.0)
                                    (* (i64->f32 (Reveal-radius reveal))
                                       (* progress (- 2.0 progress))))
                          (lambda () (terrain-items world (lambda (index) (fresh? world index))))))
             (Nil)))))

    ;; Crystals shimmer, pulsing in strength.
    (: shimmer-batch (-> Game Batch))
    (define (shimmer-batch game)
      (let* ((world (Game-world game)) (time (/ (i64->f32 (Game-shown game)) 1000.0)))
        (Batch 4 (stamp game (World-structure-version world))
               (Translucent (+ 0.45 (* 0.25 (f64->f32 (sin (f32->f64 (* 2.5 time)))))))
               (lambda ()
                 (concatenate (map (lambda (c) (at-cell (Crystal-cell c) (shimmer-parts)))
                                   (open-crystals world)))))))

    ;; During the opening, the crystals in sight pulse white to show where
    ;; the first extractor goes.
    (: beacon-batches (-> Game (List Batch)))
    (define (beacon-batches game)
      (let* ((world (Game-world game)) (time (/ (i64->f32 (Game-shown game)) 1000.0)))
        (if (opening? world)
            (list (Batch 10
                         (stamp game
                                (+ (World-structure-version world) (World-explored-version world)))
                         (Translucent (+ 0.5 (* 0.3 (f64->f32 (sin (f32->f64 (* 5.0 time)))))))
                         (lambda ()
                           (concatenate (map (lambda (c)
                                               (at-cell (Crystal-cell c)
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
    (: bar-batch (-> Game Batch))
    (define (bar-batch game)
      (let* ((world (Game-world game))
             (yaw (bar-yaw (heading-angle game)))
             (step (f32->i64 (round (* yaw 256.0)))))
        (Batch 8
               (stamp game (+ (* 2048 (+ (World-tick world) (World-explored-version world))) step))
               (Solid)
               (lambda () (bar-batch-items world yaw)))))

    (: link-batch (-> Game Batch))
    (define (link-batch game)
      (Batch 9
             (stamp game (World-structure-version (Game-world game)))
             (Translucent 0.8)
             (lambda () (link-items (Game-world game)))))

    (: cursor-batch (-> Game Batch))
    (define (cursor-batch game)
      (Batch 6 (stamp game (cursor-version game)) (Solid) (lambda () (cursor-items game))))

    (: preview-batch (-> Game Batch))
    (define (preview-batch game)
      (let ((time (/ (i64->f32 (Game-clock game)) 1000.0)))
        (Batch 7
               (stamp game (preview-version game))
               (Translucent (+ 0.45 (* 0.15 (f64->f32 (sin (f32->f64 (* 4.0 time)))))))
               (lambda () (preview-items game)))))

    (: view-game (-> Game Frame))
    (define (view-game game)
      (let* ((world (Game-world game)) (camera (game-camera game)))
        (Frame camera (camera-light camera) sky (world-motion game)
               (concatenate (list (terrain-batches game)
                                  (list (Batch 3
                                               (stamp game (World-structure-version world))
                                               (Solid)
                                               (lambda () (structure-items world)))
                                        (Batch 5
                                               (stamp game (World-tick world))
                                               (Solid)
                                               (lambda () (moving-items world)))
                                        (bar-batch game) (link-batch game)
                                        (cursor-batch game) (shimmer-batch game))
                                  (beacon-batches game)
                                  (list (preview-batch game))))
               (Nil))))

    (: filter-map (All (A B) (-> (-> A (Option B)) (List A) (List B))))
    (define (filter-map f items)
      (fold-right
       (lambda (item kept) (match (f item) ((Some value) (Cons value kept)) ((None) kept)))
       (Nil)
       items))

    ))
