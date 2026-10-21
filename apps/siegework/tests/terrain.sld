;; The seeded land: the hub, the three fronts and the crystal sites for a
;; few seeds, the whole map for seed 1, and the walking distance from the
;; hub to each nest.
(import
 (lofi base)
 (lofi io)
 (siegework grid)
 (siegework terrain))

(: cell-text (-> Cell String))
(define (cell-text cell)
  (string-append "(" (show (Cell-x cell)) "," (show (Cell-y cell)) ")"))

(: count-ground (-> Land Ground I64))
(define (count-ground land wanted)
  (vector-fold (lambda (total ground) (if (= (ground-code ground) (ground-code wanted)) (+ total 1) total)) 0 (Land-ground land)))

(: ground-code (-> Ground I64))
(define (ground-code ground)
  (match ground
    ((Grass) 0)
    ((Rock) 1)
    ((Water) 2)))

(: describe (-> I64 Unit ! console))
(define (describe seed)
  (let ((land (new-land seed)))
    (write-line (string-append "seed " (show seed) ": hub " (cell-text (Land-hub land))
                               ", fronts " (string-join (map cell-text (Land-fronts land)) " ")
                               ", grass " (show (count-ground land (Grass))) ", rock " (show (count-ground land (Rock)))
                               ", water " (show (count-ground land (Water)))))
    (write-line (string-append "  sites " (string-join (map (lambda (site) (string-append (cell-text (Site-cell site)) "x" (show (Site-rate site))))
                                                            (Land-sites land))
                                                       " ")))))

;; Each row of the map: # rock, ~ water, H the hub, N a nest, * a crystal.
(: map-row (-> Land I64 String))
(define (map-row land y)
  (list->string (map (lambda (x) (cell-char land (Cell x y))) (iota map-size))))

(: cell-char (-> Land Cell Char))
(define (cell-char land cell)
  (cond ((cell=? cell (Land-hub land)) #\H)
        ((any? (lambda (front) (cell=? front cell)) (Land-fronts land)) #\N)
        ((any? (lambda (site) (cell=? (Site-cell site) cell)) (Land-sites land)) #\*)
        (else (match (ground-at land cell) ((Grass) #\.) ((Rock) #\#) ((Water) #\~)))))

(: nest-distances (-> Land String))
(define (nest-distances land)
  (let ((field (distance-field (vector-map (lambda (ground) (match ground ((Grass) #t) (_ #f))) (Land-ground land))
                               (list (Land-hub land)))))
    (string-join (map (lambda (front) (show (vector-ref field (cell-index front)))) (Land-fronts land)) " ")))

(for-each describe (list 1 2 777 65535))
(define land (new-land 1))
(for-each (lambda (y) (write-line (map-row land y))) (iota map-size))
(write-line (string-append "walking steps from the hub to each nest: " (nest-distances land)))
(write-line (string-append "line (0,0)-(3,1): " (string-join (map cell-text (line-cells (Cell 0 0) (Cell 3 1))) " ")))
(write-line (string-append "line (0,0)-(2,2): " (string-join (map cell-text (line-cells (Cell 0 0) (Cell 2 2))) " ")))
