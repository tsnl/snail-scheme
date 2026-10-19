;; Integer fields reproduce a compact world directly from its saved seed. Route
;; searches own bounded scratch vectors, never the world's surveys or hazards.
(define-library (siegework terrain)
  (export map-width map-height hub-x hub-y cell-size cell-x cell-y cell-index
          index-x index-y inside? ground? water? deposit-rate distance within?
          Survey make-survey survey-x survey-y survey-radius surveyed?
          next-map-seed spawn-x spawn-y nest-x nest-y front-x front-y nest-site? deposit-capacity
          northern-x northern-y eastern-x eastern-y regional-deposit-x regional-deposit-y
          walking-path tunneling-path avoiding-path escape-path clear-shot? observed-shot?
          open-ground? walking-open-path avoiding-open-path escape-open-path clear-open-shot? observed-open-shot?
          CartEdge make-cart-edge cart-step-cost rail-edge rail-step? cart-path cart-escape-path)
  (import
   (scheme base)
   (scheme immutable)
   (lofi serialization)
   (only (lofi core) I32 Bool deriving)
   (only (lofi base) i32->i64))
  (begin

    ;; ---- Map coordinates ----

    (define map-width 128)
    (define map-height 128)
    (define cell-size 40)
    (define hub-x 8)
    (define hub-y 22)
    (define (cell-x x) (+ (* x cell-size) 20))
    (define (cell-y y) (+ (* y cell-size) 20))
    (define (cell-index x y) (+ x (* y map-width)))
    (define (index-x index) (remainder index map-width))
    (define (index-y index) (quotient index map-width))
    (define (inside? x y) (and (>= x 0) (< x map-width) (>= y 0) (< y map-height)))
    (define (absolute value) (if (< value 0) (- 0 value) value))
    (define (distance x y a b) (+ (absolute (- x a)) (absolute (- y b))))
    (define (within? x y a b radius)
      (<= (+ (* (- x a) (- x a)) (* (- y b) (- y b))) (* radius radius)))

    ;; ---- Seeded geography ----

    ;; Seeds are stored as 1..65535. Every field uses bounded integer products;
    ;; querying one tile neither generates the map nor advances random state.
    (define (next-map-seed seed)
      (if (or (< seed 1) (>= seed 65535)) 1 (+ seed 1)))
    (define (map-offset seed stride count)
      (remainder (remainder (* seed stride) 65521) count))
    ;; Rejection retains the circular sampling area without projecting square
    ;; corners toward its center. Both coordinates accept the same candidate;
    ;; the bounded replay needs no random state or per-query pair allocation.
    (define (spawn-offset seed attempt horizontal)
      (let ((x (- (map-offset seed 73 17) 8)) (y (- (map-offset seed 151 17) 8)))
        (cond ((<= (+ (* x x) (* y y)) 64) (if horizontal x y))
              ((= attempt 23) 0)
              (else (spawn-offset (remainder (+ (* seed 25173) 13849) 65521)
                                  (+ attempt 1) horizontal)))))
    (define (spawn-x seed) (+ 64 (spawn-offset seed 0 #t)))
    (define (spawn-y seed) (+ 64 (spawn-offset seed 0 #f)))
    ;; Five or six observation hops reach the nest. Even the farthest seed
    ;; leaves fifteen cells to the edge for its clearing and spawn lanes.
    (define (nest-offset seed horizontal)
      (let ((direction (map-offset seed 67 4))
            (major (+ 32 (map-offset seed 173 9)))
            (minor (- (map-offset seed 227 17) 8)))
        (if (= (remainder direction 2) (if horizontal 0 1))
            (if (< direction 2) major (- 0 major)) minor)))
    (define (nest-x seed) (+ (spawn-x seed) (nest-offset seed #t)))
    (define (nest-y seed) (+ (spawn-y seed) (nest-offset seed #f)))
    ;; Three fronts use the original bearing and integer rotations of ±120°.
    ;; Across every seed they remain at least sixteen cells from the map edge
    ;; and fifty-four cells apart. Clearings depend on the seed, never nest HP.
    (define (front-offset seed front horizontal)
      (let ((x (nest-offset seed #t)) (y (nest-offset seed #f))
            (turn (if (= front 1) 866 -866)))
        (if (= front 0) (if horizontal x y)
            (quotient (if horizontal (- (* -500 x) (* turn y))
                          (+ (* turn x) (* -500 y))) 1000))))
    (define (front-x seed front) (+ (spawn-x seed) (front-offset seed front #t)))
    (define (front-y seed front) (+ (spawn-y seed) (front-offset seed front #f)))
    (define (front-cell? seed front x y)
      (and (= x (front-x seed front)) (= y (front-y seed front))))
    (define (nest-site? seed x y)
      (or (front-cell? seed 0 x y) (front-cell? seed 1 x y) (front-cell? seed 2 x y)))
    (define (home-x seed x) (+ (- x (spawn-x seed)) hub-x))
    (define (home-y seed y) (+ (- y (spawn-y seed)) hub-y))
    (define (home-cell? x y) (and (>= x 0) (< x 48) (>= y 0) (< y 36)))
    (define (northern-x seed)
      (+ (- (spawn-x seed) hub-x) (if (= seed 1) 5 (+ 4 (map-offset seed 73 11)))))
    (define (northern-y seed)
      (+ (- (spawn-y seed) hub-y) (if (= seed 1) 5 (+ 3 (map-offset seed 151 4)))))
    (define (eastern-x seed)
      (let ((x (+ (- (spawn-x seed) hub-x) (if (= seed 1) 36 (+ 33 (map-offset seed 199 9))))))
        ;; The compact nest may share the eastern clearing. Keep its deposit
        ;; buildable by moving a coincident crystal one clear cell west.
        (if (nest-site? seed x (eastern-y seed)) (- x 1) x)))
    (define (eastern-y seed)
      (+ (- (spawn-y seed) hub-y) (if (= seed 1) 12 (+ 7 (map-offset seed 239 10)))))

    ;; The ridge stays east of the hub and starter. Its crossing is at least
    ;; three cells tall, and the southern edge remains a second way around it.
    (define (ridge? seed x y)
      (let ((left (if (= seed 1) 23 (+ 22 (map-offset seed 31 5))))
            (opening (if (= seed 1) 16 (+ 15 (map-offset seed 43 7))))
            (height (if (= seed 1) 4 3)))
        (and (>= x left) (<= x (+ left 1)) (< y 31)
             (or (< y opening) (>= y (+ opening height))))))
    ;; The northern mine is above this wall. Both its gap and the open strip
    ;; at x=19..21 connect it to the hub, regardless of the chosen ridge.
    (define (northern-wall? seed x y)
      (let ((row (if (= seed 1) 10 (+ 9 (map-offset seed 59 4))))
            (opening (if (= seed 1) 10 (+ 8 (map-offset seed 83 7))))
            (width (if (= seed 1) 4 3)))
        (and (= y row) (< x 19)
             (or (< x opening) (>= x (+ opening width))))))
    ;; This isolated rock bed stays below the eastern mine and beyond the
    ;; ridge crossing. All its edges leave room to walk around it.
    (define (southern-rock? seed x y)
      (let ((left (if (= seed 1) 32 (+ 31 (map-offset seed 107 7))))
            (top (if (= seed 1) 25 (+ 24 (map-offset seed 127 5)))))
        (and (>= x left) (<= x (+ left 6)) (>= y top) (<= y (+ top 3)))))
    (define (home-ground? seed x y)
      (and (not (ridge? seed x y)) (not (northern-wall? seed x y))
           (not (southern-rock? seed x y))))

    ;; Each 32-cell region contains one bounded, bending ellipse or open land.
    ;; The outer four rows and columns stay clear, joining neighboring regions
    ;; into walking corridors. The translated starter geography has its own
    ;; crossings; seed 1 preserves that entire 48-by-36 neighborhood exactly.
    (define (region-value seed x y stride count)
      (map-offset (+ seed (+ (* (quotient x 32) 97) (* (quotient y 32) 193))) stride count))
    (define (triangle value)
      (- (absolute (- (remainder value 24) 12)) 6))
    (define (region-shape? seed x y width height)
      (let* ((v (- (remainder y 32) 16))
             (bend (quotient (triangle (+ (remainder y 32) (map-offset seed 41 24))) 3))
             (u (- (remainder x 32) (+ 16 bend)))
             (w (+ width (region-value seed x y 109 3))))
        (<= (+ (* (* u u) (* height height)) (* (* v v) (* w w))) (* (* w w) (* height height)))))
    (define (region-water? seed x y)
      (and (= (region-value seed x y 137 5) 0) (region-shape? seed x y 5 9)))
    (define (region-mountain? seed x y)
      (let ((kind (region-value seed x y 137 5)))
        (and (> kind 0) (< kind 4) (region-shape? seed x y 3 11))))
    (define (nest-clearing? seed x y)
      (or (within? x y (front-x seed 0) (front-y seed 0) 10)
          (within? x y (front-x seed 1) (front-y seed 1) 10)
          (within? x y (front-x seed 2) (front-y seed 2) 10)))
    (define (water? seed x y)
      (and (inside? x y) (not (home-cell? (home-x seed x) (home-y seed y)))
           (not (nest-clearing? seed x y)) (region-water? seed x y)))
    (define (ground? seed x y)
      (and (inside? x y)
           (or (nest-clearing? seed x y)
               (let ((hx (home-x seed x)) (hy (home-y seed y)))
                 (if (home-cell? hx hy) (home-ground? seed hx hy)
                     (and (not (region-water? seed x y))
                          (not (region-mountain? seed x y))))))))
    ;; Permanent breaches are sparse map edits; water is never opened by a
    ;; rock excavation. Path callers may also admit known unfinished dig sites.
    (define (opened-cell? opened cell)
      (and (not (null? opened))
           (or (= (car opened) cell) (opened-cell? (cdr opened) cell))))
    (define (open-ground? seed opened x y)
      (and (inside? x y)
           (or (ground? seed x y)
               (and (not (water? seed x y)) (opened-cell? opened (cell-index x y))))))
    ;; Regional deposits sit in the open corner corridors, so their sites
    ;; cannot become islands inside a lake or a mountain. Home mines retain
    ;; their stronger north/east progression and the nearby two-ore starter.
    (define (regional-deposit-x seed rx ry) (+ (+ (* rx 32) 2) (region-value seed (* rx 32) (* ry 32) 157 3)))
    (define (regional-deposit-y seed rx ry) (+ (+ (* ry 32) 2) (region-value seed (* rx 32) (* ry 32) 181 3)))
    (define (regional-deposit? seed x y)
      (and (= (remainder x 32) (+ 2 (region-value seed x y 157 3)))
           (= (remainder y 32) (+ 2 (region-value seed x y 181 3)))))
    (define (deposit-rate seed x y)
      (cond ((or (not (inside? x y)) (nest-site? seed x y)) 0)
            ((and (= x (+ (spawn-x seed) 4)) (= y (- (spawn-y seed) 2))) 2)
            ((and (= x (northern-x seed)) (= y (northern-y seed))) 3)
            ((and (= x (eastern-x seed)) (= y (eastern-y seed))) 6)
            ((home-cell? (home-x seed x) (home-y seed y)) 0)
            ((regional-deposit? seed x y) (+ 2 (region-value seed x y 211 5)))
            (else 0)))
    (define (deposit-capacity seed x y)
      (let ((rate (deposit-rate seed x y)))
        (if (= rate 0) 0 (* 300 rate))))

    ;; ---- Direct fire crosses every touched grid cell ----

    ;; Integer cross-products order the next vertical and horizontal boundary.
    ;; An exact corner touches both neighboring cells, so rocks cannot be shot
    ;; through diagonally. Planning treats unknown cells as blocked; actual fire
    ;; tests physical rock along the same segment.
    (define (shot-cell? seed opened surveys known x y)
      (and (or (not known) (surveyed? surveys x y))
           (or (open-ground? seed opened x y) (water? seed x y))))
    (define (shot-cells? seed opened surveys known x y tx ty sx sy nx ny dx dy)
      (and (shot-cell? seed opened surveys known x y)
           (or (and (= x tx) (= y ty))
               (cond ((or (= dx 0) (and (> dy 0) (< (* ny dx) (* nx dy))))
                      (shot-cells? seed opened surveys known x (+ y sy) tx ty sx sy nx (+ ny cell-size) dx dy))
                     ((or (= dy 0) (< (* nx dy) (* ny dx)))
                      (shot-cells? seed opened surveys known (+ x sx) y tx ty sx sy (+ nx cell-size) ny dx dy))
                     (else (and (shot-cell? seed opened surveys known (+ x sx) y)
                                (shot-cell? seed opened surveys known x (+ y sy))
                                (shot-cells? seed opened surveys known (+ x sx) (+ y sy) tx ty sx sy
                                             (+ nx cell-size) (+ ny cell-size) dx dy)))))))
    (define (shot-segment? seed opened surveys known x y a b)
      (let ((cx (quotient x cell-size)) (cy (quotient y cell-size))
            (dx (absolute (- a x))) (dy (absolute (- b y)))
            (sx (if (< x a) 1 -1)) (sy (if (< y b) 1 -1)))
        (shot-cells? seed opened surveys known cx cy (quotient a cell-size) (quotient b cell-size) sx sy
                     (if (> sx 0) (- (* (+ cx 1) cell-size) x) (- x (* cx cell-size)))
                     (if (> sy 0) (- (* (+ cy 1) cell-size) y) (- y (* cy cell-size))) dx dy)))
    (define (clear-open-shot? seed opened x y a b) (shot-segment? seed opened (empty-list) #f x y a b))
    (define (clear-shot? seed x y a b) (clear-open-shot? seed (empty-list) x y a b))
    (define (observed-open-shot? seed opened surveys x y a b) (shot-segment? seed opened surveys #t x y a b))
    (define (observed-shot? seed surveys x y a b) (observed-open-shot? seed (empty-list) surveys x y a b))

    ;; ---- Geography remains known after observation is lost ----

    (define-immutable-record Survey make-survey
      (x I32 survey-x survey-x-set)
      (y I32 survey-y survey-y-set)
      (radius I32 survey-radius survey-radius-set)
      (deriving derive-serialize derive-deserialize))
    (define (surveyed? surveys x y)
      (and (not (null? surveys))
           (or (within? x y (survey-x (car surveys)) (survey-y (car surveys))
                        (survey-radius (car surveys)))
               (surveyed? (cdr surveys) x y))))

    ;; ---- Sparse A* searches own bounded scratch ----

    ;; A hash slot identifies one discovered cell for this attempt. Parent links
    ;; and the heap retain that slot, so the table never resizes in place. At most
    ;; 6144 cells occupy 8192 slots: probing always finds a vacant slot. Small
    ;; jobs start smaller and retry after budget exhaustion, never after a proven
    ;; empty frontier. Five cell vectors hold at most 8192 I32s each; three
    ;; counters track discoveries, heap length and budget exhaustion.
    ;; Heap position -1 means closed; an absent hash key means undiscovered.
    (define-immutable-record Search make-search
      (seed I32 search-seed search-seed-set)
      (opened (List I32) search-opened search-opened-set)
      (fast (List CartEdge) search-fast search-fast-set)
      (walking-cost I32 search-walking-cost search-walking-cost-set)
      (target I32 search-target search-target-set)
      (weight I32 search-weight search-weight-set)
      (surveys (List Survey) search-surveys search-surveys-set)
      (blocked (List Survey) search-blocked search-blocked-set)
      (warnings (List Survey) search-warnings search-warnings-set)
      (unrestricted Bool search-unrestricted search-unrestricted-set)
      (tunneling Bool search-tunneling search-tunneling-set)
      (capacity I32 search-capacity search-capacity-set)
      (cells (Vector I32) search-cells search-cells-set)
      (parents (Vector I32) search-parents search-parents-set)
      (steps (Vector I32) search-steps search-steps-set)
      (heap (Vector I32) search-heap search-heap-set)
      (positions (Vector I32) search-positions search-positions-set)
      (counts (Vector I32) search-counts search-counts-set))
    (define (read-cell cells index) (vector-ref cells (i32->i64 index)))
    (define (write-cell! cells index value) (vector-set! cells (i32->i64 index) value))
    (define (route-weight start target)
      (if (and (>= target 0)
               (> (distance (index-x start) (index-y start) (index-x target) (index-y target)) 96)) 2 1))
    (define (new-search seed opened fast walking-cost start target surveys blocked warnings unrestricted tunneling capacity)
      (make-search seed opened fast walking-cost target (route-weight start target) surveys blocked warnings unrestricted tunneling capacity
                   (make-vector (i32->i64 capacity) -1)
                   (make-vector (i32->i64 capacity) -1)
                   (make-vector (i32->i64 capacity) 0)
                   (make-vector (i32->i64 capacity) 0)
                   (make-vector (i32->i64 capacity) -1)
                   (make-vector (i32->i64 3) 0)))
    (define (heap-size search) (read-cell (search-counts search) 1))
    (define (heap-size-set! search count) (write-cell! (search-counts search) 1 count))
    (define (search-full? search) (= (read-cell (search-counts search) 2) 1))
    (define (cell-slot search cell slot)
      (let ((key (read-cell (search-cells search) slot)))
        (if (or (= key -1) (= key cell)) slot
            (cell-slot search cell (remainder (+ slot 1) (search-capacity search))))))
    (define (find-slot search cell)
      (cell-slot search cell (remainder (* cell 193) (search-capacity search))))
    (define (remaining-steps search slot)
      (let ((cell (read-cell (search-cells search) slot)) (target (search-target search)))
        (if (< target 0) 0 (distance (index-x cell) (index-y cell) (index-x target) (index-y target)))))
    (define (earlier-slot? search a b)
      (let* ((ga (read-cell (search-steps search) a)) (gb (read-cell (search-steps search) b))
             (fa (+ ga (* (search-weight search) (remaining-steps search a))))
             (fb (+ gb (* (search-weight search) (remaining-steps search b)))))
        (or (< fa fb) (and (= fa fb)
                           (or (> ga gb) (and (= ga gb)
                                              (< (read-cell (search-cells search) a)
                                                 (read-cell (search-cells search) b))))))))

    ;; ---- The frontier heap supports shorter paths to open cells ----

    ;; Local trips use consistent Manhattan distance and return shortest routes.
    ;; Trips farther than 96 cells double that heuristic to cross large regions
    ;; within the discovery budget; these routes are valid, not always shortest.
    ;; All modes improve open cells, while closed cells keep their chosen parent.
    (define (heap-swap! search a b)
      (let ((left (read-cell (search-heap search) a)) (right (read-cell (search-heap search) b)))
        (write-cell! (search-heap search) a right)
        (write-cell! (search-heap search) b left)
        (write-cell! (search-positions search) left b)
        (write-cell! (search-positions search) right a)))
    (define (heap-up! search child)
      (when (> child 0)
        (let ((parent (quotient (- child 1) 2)))
          (when (earlier-slot? search (read-cell (search-heap search) child)
                               (read-cell (search-heap search) parent))
            (heap-swap! search child parent)
            (heap-up! search parent)))))
    (define (heap-down! search parent)
      (let ((left (+ (* parent 2) 1)) (right (+ (* parent 2) 2)))
        (when (< left (heap-size search))
          (let ((child (if (and (< right (heap-size search))
                                (earlier-slot? search (read-cell (search-heap search) right)
                                               (read-cell (search-heap search) left))) right left)))
            (when (earlier-slot? search (read-cell (search-heap search) child)
                                 (read-cell (search-heap search) parent))
              (heap-swap! search child parent)
              (heap-down! search child))))))
    (define (heap-push! search slot)
      (let ((tail (heap-size search)))
        (write-cell! (search-heap search) tail slot)
        (write-cell! (search-positions search) slot tail)
        (heap-size-set! search (+ tail 1))
        (heap-up! search tail)))
    (define (heap-pop! search)
      (let ((slot (read-cell (search-heap search) 0)) (tail (- (heap-size search) 1)))
        (heap-size-set! search tail)
        (when (> tail 0)
          (let ((last (read-cell (search-heap search) tail)))
            (write-cell! (search-heap search) 0 last)
            (write-cell! (search-positions search) last 0)
            (heap-down! search 0)))
        (write-cell! (search-positions search) slot -1)
        slot))

    ;; ---- Traversal rules share an exact adjacent-cell search ----

    ;; An undirected adjacent edge fits in two slots per map cell: east or
    ;; south. Cart search and physical motion consult the same edge identities.
    (define (rail-edge a b)
      (+ (* (if (< a b) a b) 2) (if (= (index-y a) (index-y b)) 0 1)))
    ;; Costs share a forty-unit walking scale. Tower levels supply costs
    ;; 4, 2 and 1; overlapping links offer the fastest available service.
    (define-immutable-record CartEdge make-cart-edge
      (id I32 cart-edge-id cart-edge-id-set)
      (cost I32 cart-edge-cost cart-edge-cost-set))
    (define (cart-edge-price fast edge fallback)
      (if (null? fast) fallback
          (let ((service (car fast)))
            (cart-edge-price (cdr fast) edge
                             (if (and (= (cart-edge-id service) edge) (< (cart-edge-cost service) fallback))
                                 (cart-edge-cost service) fallback)))))
    (define (cart-step-cost fast a b)
      (if (= (distance (index-x a) (index-y a) (index-x b) (index-y b)) 1)
          (cart-edge-price fast (rail-edge a b) 40) 40))
    (define (rail-step? fast a b) (< (cart-step-cost fast a b) 40))
    (define (traversable? seed opened x y tunneling)
      (and (inside? x y) (if tunneling (not (water? seed x y)) (open-ground? seed opened x y))))
    (define (search-enter? search x y)
      (and (traversable? (search-seed search) (search-opened search) x y (search-tunneling search))
           (or (search-unrestricted search) (surveyed? (search-surveys search) x y))
           (not (surveyed? (search-blocked search) x y))))
    (define (discover-cell! search slot cell parent steps)
      (let ((count (read-cell (search-counts search) 0)))
        (if (>= count (quotient (* (search-capacity search) 3) 4))
            (write-cell! (search-counts search) 2 1)
            (begin (write-cell! (search-counts search) 0 (+ count 1))
                   (write-cell! (search-cells search) slot cell)
                   (write-cell! (search-parents search) slot parent)
                   (write-cell! (search-steps search) slot steps)
                   (heap-push! search slot)))))
    (define (improve-cell! search slot parent steps)
      (let ((position (read-cell (search-positions search) slot)))
        (when (and (>= position 0) (< steps (read-cell (search-steps search) slot)))
          (write-cell! (search-parents search) slot parent)
          (write-cell! (search-steps search) slot steps)
          (heap-up! search position))))
    (define (visit-cell! search parent x y)
      (when (and (not (search-full? search)) (search-enter? search x y))
        (let* ((cell (cell-index x y)) (slot (find-slot search cell))
               (previous (read-cell (search-cells search) parent))
               (steps (+ (read-cell (search-steps search) parent)
                         (cart-edge-price (search-fast search) (rail-edge previous cell) (search-walking-cost search)))))
          (if (= (read-cell (search-cells search) slot) -1)
              (discover-cell! search slot cell parent steps)
              (improve-cell! search slot parent steps)))))
    (define (visit-neighbors! search slot)
      (let* ((cell (read-cell (search-cells search) slot)) (x (index-x cell)) (y (index-y cell)))
        (visit-cell! search slot (+ x 1) y)
        (visit-cell! search slot (- x 1) y)
        (visit-cell! search slot x (+ y 1))
        (visit-cell! search slot x (- y 1))))
    (define (search-destination? search slot)
      (let ((cell (read-cell (search-cells search) slot)))
        (if (>= (search-target search) 0) (= cell (search-target search))
            (not (surveyed? (search-warnings search) (index-x cell) (index-y cell))))))
    (define (search-route! search)
      (if (or (= (heap-size search) 0) (search-full? search)) -1
          (let ((slot (heap-pop! search)))
            (if (search-destination? search slot) slot
                (begin (visit-neighbors! search slot) (search-route! search))))))
    ;; Routes omit the start and include the exact destination. A failed budget
    ;; or overlong route returns no route, never a prefix mistaken for arrival.
    (define (route-back search slot remaining route)
      (let ((parent (read-cell (search-parents search) slot)))
        (cond ((= parent slot) route)
              ((= remaining 0) (empty-list))
              (else (route-back search parent (- remaining 1)
                                (cons (read-cell (search-cells search) slot) route))))))
    (define (search-path seed opened fast walking-cost start target surveys blocked warnings unrestricted tunneling capacity)
      (let* ((search (new-search seed opened fast walking-cost start target surveys blocked warnings unrestricted tunneling capacity))
             (root (find-slot search start)))
        (discover-cell! search root start root 0)
        (let ((destination (search-route! search)))
          (cond ((>= destination 0) (route-back search destination 1024 (empty-list)))
                ((and (search-full? search) (< capacity 8192))
                 (search-path seed opened fast walking-cost start target surveys blocked warnings unrestricted tunneling (* capacity 2)))
                (else (empty-list))))))
    (define (initial-capacity length)
      (cond ((< length 64) 512) ((< length 128) 1024) ((< length 256) 2048)
            ((< length 512) 4096) (else 8192)))
    (define (find-path seed opened fast walking-cost x y a b surveys hazards unrestricted tunneling)
      (if (not (and (traversable? seed opened x y tunneling) (traversable? seed opened a b tunneling)
                    (or unrestricted (surveyed? surveys a b)) (not (surveyed? hazards a b))))
          (empty-list)
          (search-path seed opened fast walking-cost (cell-index x y) (cell-index a b) surveys hazards (empty-list)
                       unrestricted tunneling (initial-capacity (distance x y a b)))))
    (define (walking-open-path seed opened x y a b surveys unrestricted)
      (find-path seed opened (empty-list) 1 x y a b surveys (empty-list) unrestricted #f))
    (define (walking-path seed x y a b surveys unrestricted)
      (walking-open-path seed (empty-list) x y a b surveys unrestricted))
    (define (tunneling-path seed x y a b)
      (find-path seed (empty-list) (empty-list) 1 x y a b (empty-list) (empty-list) #t #t))
    (define (avoiding-open-path seed opened x y a b surveys hazards)
      (find-path seed opened (empty-list) 1 x y a b surveys hazards #f #f))
    (define (avoiding-path seed x y a b surveys hazards)
      (avoiding-open-path seed (empty-list) x y a b surveys hazards))
    (define (cart-path seed opened fast x y a b surveys hazards)
      (find-path seed opened fast (if (null? fast) 1 40) x y a b surveys hazards #f #f))

    ;; ---- Emergency escape crosses warnings but not enemy positions ----

    ;; A target of -1 searches for the first safe cell with heuristic zero.
    ;; That is the nearest safe ground under the same heap and traversal rules.
    ;; Injecting the start permits departure even when that cell is hazardous.
    (define (occupied-hazards hazards)
      (if (null? hazards) (empty-list)
          (cons (make-survey (survey-x (car hazards)) (survey-y (car hazards)) 0)
                (occupied-hazards (cdr hazards)))))
    (define (escape-open-path seed opened x y surveys hazards)
      (if (not (open-ground? seed opened x y)) (empty-list)
          (search-path seed opened (empty-list) 1 (cell-index x y) -1 surveys (occupied-hazards hazards) hazards #f #f 512)))
    (define (cart-escape-path seed opened fast x y surveys hazards)
      (if (not (open-ground? seed opened x y)) (empty-list)
          (search-path seed opened fast (if (null? fast) 1 40) (cell-index x y) -1 surveys
                       (occupied-hazards hazards) hazards #f #f 512)))
    (define (escape-path seed x y surveys hazards)
      (escape-open-path seed (empty-list) x y surveys hazards))))
