;; The seeded land: the biome, hub, fronts, ground and crystal sites for
;; eight seeds, the whole map of the first seed of each biome with the
;; walking distance from its hub to each nest, what holds on every map
;; across 64 seeds, and two straight lines.
(import
 (snail core base)
 (snail core io)
 (siegework grid)
 (siegework terrain))

(define (cell-text (cell Cell)) (→ String)
  (string-append "(" (show (::x cell)) "," (show (::y cell)) ")"))

(define (ground-char (ground Ground)) (→ Char)
  (match ground
    ((Open) #\.)
    ((Rock) #\#)
    ((Water) #\~)
    ((Ice) #\=)))

(define (count-ground (land Land) (wanted Ground)) (→ I64)
  (vector-fold
   (lambda (total ground) (if (char=? (ground-char ground) (ground-char wanted)) (+ total 1) total))
   0
   (::ground land)))

(define (describe (seed I64)) (→ Unit) (! console)
  (let ((land (new-land seed)))
    (write-line (string-append "seed "
                               (show seed)
                               ", "
                               (biome-name (::biome land))
                               ": hub "
                               (cell-text (::hub land))
                               ", fronts " (string-join (map cell-text (::fronts land)) " ")
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
                                                   (string-append (cell-text (::cell site))
                                                                  "x"
                                                                  (show (::rate site))))
                                                 (::sites land))
                                            " ")))))

;; Each row of the map: . open, # rock, ~ water, = ice, H the hub, N a
;; nest, * a crystal.
(define (map-row (land Land) (y I64)) (→ String)
  (list->string (map (lambda (x) (cell-char land (Cell x y))) (iota map-size))))

(define (cell-char (land Land) (cell Cell)) (→ Char)
  (cond ((cell=? cell (::hub land)) #\H)
        ((any? (lambda (front) (cell=? front cell)) (::fronts land)) #\N)
        ((any? (lambda (site) (cell=? (::cell site) cell)) (::sites land)) #\*)
        (else (ground-char (ground-at land cell)))))

(define (steps-from-hub (land Land) (crosses? (dyn (Fn Ground → Bool)))) (→ (Vector I64))
  (distance-field (vector-map crosses? (::ground land)) (list (::hub land))))

(define (walkable? (ground Ground)) (→ Bool)
  (match ground ((Open) #t) ((Ice) #t) (_ #f)))

(define (nest-distances (land Land)) (→ String)
  (let ((field (steps-from-hub land walkable?)))
    (string-join
     (map (lambda (front) (show (vector-ref field (cell-index front)))) (::fronts land))
     " ")))

;; Every nest can walk to the hub, and every crystal is on open ground the
;; hub can wire toward without crossing rock.
(define (playable? (land Land)) (→ Bool)
  (let ((walk (steps-from-hub land walkable?))
        (wire (steps-from-hub land (lambda (g) (match g ((Rock) #f) (_ #t))))))
    (and (every? (lambda (front) (>= (vector-ref walk (cell-index front)) 0)) (::fronts land))
         (every? (lambda (site)
                   (and (char=? (ground-char (ground-at land (::cell site))) #\.)
                        (>= (vector-ref wire (cell-index (::cell site))) 0)))
                 (::sites land)))))

(define (biome-count (lands (List Land)) (biome Biome)) (→ String)
  (string-append (biome-name biome)
                 " "
                 (show (length (filter (lambda (land)
                                         (string=? (biome-name (::biome land))
                                                   (biome-name biome)))
                                       lands)))))

(define (show-map (land Land)) (→ Unit) (! console)
  (write-line (string-append (biome-name (::biome land)) ", seed " (show (::seed land)) ":"))
  (for-each (lambda (y) (write-line (map-row land y))) (iota map-size))
  (write-line (string-append "walking steps from the hub to each nest: " (nest-distances land))))

(define (first-of (biome Biome) (seed I64)) (→ Land)
  (let ((land (new-land seed)))
    (if (string=? (biome-name (::biome land)) (biome-name biome))
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
                                   (string-join (map (lambda (land) (show (::seed land))) broken)
                                                " "))))))
(for-each (lambda (biome) (show-map (first-of biome 1)))
          (list (Meadow) (Desert) (Tundra) (Archipelago)))
(write-line (string-append "line (0,0)-(3,1): "
                           (string-join (map cell-text (line-cells (Cell 0 0) (Cell 3 1))) " ")))
(write-line (string-append "line (0,0)-(2,2): "
                           (string-join (map cell-text (line-cells (Cell 0 0) (Cell 2 2))) " ")))
