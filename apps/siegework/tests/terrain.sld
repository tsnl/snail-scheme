;; The seeded land: the biome, hub, fronts, ground and crystal sites for
;; eight seeds, the whole map of the first seed of each biome with the
;; walking distance from its hub to each nest, what holds on every map
;; across 64 seeds, and two straight lines.
(import
 (snail core base)
 (snail core io)
 (siegework grid)
 (siegework terrain))

(: cell-text (-> Cell String))
(define (cell-text cell)
  (string-append "(" (show (Cell-x cell)) "," (show (Cell-y cell)) ")"))

(: ground-char (-> Ground Char))
(define (ground-char ground)
  (match ground
    ((Open) #\.)
    ((Rock) #\#)
    ((Water) #\~)
    ((Ice) #\=)))

(: count-ground (-> Land Ground I64))
(define (count-ground land wanted)
  (vector-fold
   (lambda (total ground) (if (char=? (ground-char ground) (ground-char wanted)) (+ total 1) total))
   0
   (Land-ground land)))

(: describe (-> I64 Unit ! console))
(define (describe seed)
  (let ((land (new-land seed)))
    (write-line (string-append "seed "
                               (show seed)
                               ", "
                               (biome-name (Land-biome land))
                               ": hub "
                               (cell-text (Land-hub land))
                               ", fronts " (string-join (map cell-text (Land-fronts land)) " ")
                               ", open "
                               (show (count-ground land (Open)))
                               ", rock "
                               (show (count-ground land (Rock)))
                               ", water "
                               (show (count-ground land (Water)))
                               ", ice "
                               (show (count-ground land (Ice)))))
    (write-line (string-append "  sites "
                               (string-join (map (lambda (site)
                                                   (string-append (cell-text (Site-cell site))
                                                                  "x"
                                                                  (show (Site-rate site))))
                                                 (Land-sites land))
                                            " ")))))

;; Each row of the map: . open, # rock, ~ water, = ice, H the hub, N a
;; nest, * a crystal.
(: map-row (-> Land I64 String))
(define (map-row land y)
  (list->string (map (lambda (x) (cell-char land (Cell x y))) (iota map-size))))

(: cell-char (-> Land Cell Char))
(define (cell-char land cell)
  (cond ((cell=? cell (Land-hub land)) #\H)
        ((any? (lambda (front) (cell=? front cell)) (Land-fronts land)) #\N)
        ((any? (lambda (site) (cell=? (Site-cell site) cell)) (Land-sites land)) #\*)
        (else (ground-char (ground-at land cell)))))

(: steps-from-hub (-> Land (-> Ground Bool) (Vector I64)))
(define (steps-from-hub land crosses?)
  (distance-field (vector-map crosses? (Land-ground land)) (list (Land-hub land))))

(: walkable? (-> Ground Bool))
(define (walkable? ground)
  (match ground ((Open) #t) ((Ice) #t) (_ #f)))

(: nest-distances (-> Land String))
(define (nest-distances land)
  (let ((field (steps-from-hub land walkable?)))
    (string-join
     (map (lambda (front) (show (vector-ref field (cell-index front)))) (Land-fronts land))
     " ")))

;; Every nest can walk to the hub, and every crystal is on open ground the
;; hub can wire toward without crossing rock.
(: playable? (-> Land Bool))
(define (playable? land)
  (let ((walk (steps-from-hub land walkable?))
        (wire (steps-from-hub land (lambda (g) (match g ((Rock) #f) (_ #t))))))
    (and (every? (lambda (front) (>= (vector-ref walk (cell-index front)) 0)) (Land-fronts land))
         (every? (lambda (site)
                   (and (char=? (ground-char (ground-at land (Site-cell site))) #\.)
                        (>= (vector-ref wire (cell-index (Site-cell site))) 0)))
                 (Land-sites land)))))

(: biome-count (-> (List Land) Biome String))
(define (biome-count lands biome)
  (string-append (biome-name biome)
                 " "
                 (show (length (filter (lambda (land)
                                         (string=? (biome-name (Land-biome land))
                                                   (biome-name biome)))
                                       lands)))))

(: show-map (-> Land Unit ! console))
(define (show-map land)
  (write-line (string-append (biome-name (Land-biome land)) ", seed " (show (Land-seed land)) ":"))
  (for-each (lambda (y) (write-line (map-row land y))) (iota map-size))
  (write-line (string-append "walking steps from the hub to each nest: " (nest-distances land))))

(: first-of (-> Biome I64 Land))
(define (first-of biome seed)
  (let ((land (new-land seed)))
    (if (string=? (biome-name (Land-biome land)) (biome-name biome))
        land
        (first-of biome (+ seed 1)))))

(for-each describe (list 1 2 3 4 5 6 7 8))
(let ((lands (map (lambda (i) (new-land (+ i 1))) (iota 64))))
  (write-line (string-append "biomes on seeds 1 to 64: "
                             (string-join (map (lambda (b) (biome-count lands b))
                                               (list (Meadow) (Desert) (Tundra) (Archipelago)))
                                          ", ")))
  (write-line (string-append "seeds where a nest cannot walk in or a crystal cannot be wired: "
                             (let ((broken (filter (lambda (land) (not (playable? land))) lands)))
                               (if (null? broken)
                                   "none"
                                   (string-join (map (lambda (land) (show (Land-seed land))) broken)
                                                " "))))))
(for-each (lambda (biome) (show-map (first-of biome 1)))
          (list (Meadow) (Desert) (Tundra) (Archipelago)))
(write-line (string-append "line (0,0)-(3,1): "
                           (string-join (map cell-text (line-cells (Cell 0 0) (Cell 3 1))) " ")))
(write-line (string-append "line (0,0)-(2,2): "
                           (string-join (map cell-text (line-cells (Cell 0 0) (Cell 2 2))) " ")))
