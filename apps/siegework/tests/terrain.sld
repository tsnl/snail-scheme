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
  (string-append "(" (show (● cell x)) "," (show (● cell y)) ")"))

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
   (● land ground)))

(define (describe (seed I64)) (→ Unit) (! output-port)
  (let ((land (new-land seed)))
    (write-line (string-append "seed "
                               (show seed)
                               ", "
                               (biome-name (● land biome))
                               ": hub "
                               (cell-text (● land hub))
                               ", fronts " (string-join (map cell-text (● land fronts)) " ")
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
                                                   (string-append (cell-text (● site cell))
                                                                  "x"
                                                                  (show (● site rate))))
                                                 (● land sites))
                                            " ")))))

;; Each row of the map: . open, # rock, ~ water, = ice, H the hub, N a
;; nest, * a crystal.
(define (map-row (land Land) (y I64)) (→ String)
  (list->string (map (lambda (x) (cell-char land (Cell x y))) (iota map-size))))

(define (cell-char (land Land) (cell Cell)) (→ Char)
  (cond ((cell=? cell (● land hub)) #\H)
        ((any? (lambda (front) (cell=? front cell)) (● land fronts)) #\N)
        ((any? (lambda (site) (cell=? (● site cell) cell)) (● land sites)) #\*)
        (else (ground-char (ground-at land cell)))))

(define (steps-from-hub (land Land) (crosses? (Fn Ground → Bool))) (→ (Vector I64))
  (distance-field (vector-map crosses? (● land ground)) (list (● land hub))))

(define (walkable? (ground Ground)) (→ Bool)
  (match ground ((Open) #t) ((Ice) #t) (_ #f)))

(define (nest-distances (land Land)) (→ String)
  (let ((field (steps-from-hub land walkable?)))
    (string-join
     (map (lambda (front) (show (vector-ref field (cell-index front)))) (● land fronts))
     " ")))

;; Every nest can walk to the hub, and every crystal is on open ground the
;; hub can wire toward without crossing rock.
(define (playable? (land Land)) (→ Bool)
  (let ((walk (steps-from-hub land walkable?))
        (wire (steps-from-hub land (lambda (g) (match g ((Rock) #f) (_ #t))))))
    (and (every? (lambda (front) (>= (vector-ref walk (cell-index front)) 0)) (● land fronts))
         (every? (lambda (site)
                   (and (char=? (ground-char (ground-at land (● site cell))) #\.)
                        (>= (vector-ref wire (cell-index (● site cell))) 0)))
                 (● land sites)))))

(define (biome-count (lands (List Land)) (biome Biome)) (→ String)
  (string-append (biome-name biome)
                 " "
                 (show (length (filter (lambda (land)
                                         (string=? (biome-name (● land biome))
                                                   (biome-name biome)))
                                       lands)))))

(define (show-map (land Land)) (→ Unit) (! output-port)
  (write-line (string-append (biome-name (● land biome)) ", seed " (show (● land seed)) ":"))
  (for-each (lambda (y) (write-line (map-row land y))) (iota map-size))
  (write-line (string-append "walking steps from the hub to each nest: " (nest-distances land))))

(define (first-of (biome Biome) (seed I64)) (→ Land)
  (let ((land (new-land seed)))
    (if (string=? (biome-name (● land biome)) (biome-name biome))
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
                                   (string-join (map (lambda (land) (show (● land seed))) broken)
                                                " "))))))
(for-each (lambda (biome) (show-map (first-of biome 1)))
          (list (Meadow) (Desert) (Tundra) (Archipelago)))
(write-line (string-append "line (0,0)-(3,1): "
                           (string-join (map cell-text (line-cells (Cell 0 0) (Cell 3 1))) " ")))
(write-line (string-append "line (0,0)-(2,2): "
                           (string-join (map cell-text (line-cells (Cell 0 0) (Cell 2 2))) " ")))
