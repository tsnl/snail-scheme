;; Canonical bare Lofi. See migration.json for source provenance.

(import (lofi base) (lofi datum) (lofi read) (lofi io))

(def Optional (datatype ( T) (absent) (present (value T optional-value))))

(def Reachable (datatype ()
  (reachable-record
    (size (Ref I64) reachable-size)
    (next (Ref (Optional Reachable)) reachable-next))))

(def Coordinate (datatype () (coordinate (x I64 coordinate-x) (y I64 coordinate-y))))

(def Cell (datatype ()
  (uninitialized-cell)
  (cell-record
    (reachable (Ref Reachable) cell-reachable-field)
    (id (Ref Coordinate) cell-id-field)
    (walls (Ref I64) cell-walls-field)
    (parent (Ref (Optional Cell)) cell-parent-field)
    (mark (Ref Bool) cell-mark-field))))

(def Wall (datatype ()
  (wall-record
    (owner (Ref Cell) wall-owner-field)
    (neighbor (Ref Cell) wall-neighbor-field)
    (bit (Ref I64) wall-bit-field))))

(def HexArray (datatype ()
  (harr-record
    (rows (Ref I64) harr-rows-field)
    (columns (Ref I64) harr-columns-field)
    (elements (Ref (Vector Cell)) harr-elements-field))))

(def Entrances (datatype ()
  (entrances (top (Optional I64) entrance-top) (bottom (Optional I64) entrance-bottom))))

(def LongestPath (datatype ()
  (longest-path
    (length I64 longest-length)
    (top (Optional I64) longest-top)
    (bottom (Optional I64) longest-bottom))))

(def Maze (datatype ()
  (maze-result (cells HexArray maze-cells) (entrance I64 maze-entrance) (exit I64 maze-exit))))

(def Output (datatype ()
  (initial-output)
  (character-output (characters (List Char) output-characters))
  (other-output)))

(def present? (All (T) (-> (Optional T) Bool))
  (lambda (value.9) (match value.9 ((absent) #f) ((present item) #t))))

(def same-set?
  (lambda (left.2 right.1) (ref-eq? (reachable-size left.2) (reachable-size right.1))))

(def same-set-next?
  (lambda (left.1 next.2) (if (present? next.2) (same-set? left.1 (optional-value next.2)) #f)))

(def same-cell? (lambda (left right) (ref-eq? (cell-walls-field left) (cell-walls-field right))))

(def same-cell-parent?
  (lambda (cell.2 parent.1)
    (if (present? parent.1) (same-cell? cell.2 (optional-value parent.1)) #f)))

(def maze-zero? (lambda (value.8) (= value.8 (ann 0 I64))))

(def maze-odd? (lambda (value.7) (not (= (remainder value.7 (ann 2 I64)) (ann 0 I64)))))

(def maze-exact-integer? (-> I64 Bool) (lambda (value.6) #t))

(def maze-reverse (All (T) (-> (List T) (List T)))
  (lambda (values.1)
    (((lambda () (begin (def loop.14 (lambda (values.2 result.5) (if (null? values.2) result.5 (loop.14 (cdr values.2) (cons (car values.2) result.5))))) loop.14)))
      values.1
      (empty-list ))))

(def vector-until-rev (All (T) (-> (-> T Bool) (Vector T) Unit))
  (lambda (procedure values)
    (((lambda () (begin (def loop.13 (lambda (index.1) (if (>= index.1 (ann 0 I64)) (begin (if (procedure (vector-ref values index.1)) (unit) (begin (loop.13 (- index.1 (ann 1 I64))) (unit))) (unit)) (unit)))) loop.13)))
      (- (vector-length values) (ann 1 I64)))))

(def same-characters?
  (lambda (actual.1 expected.2)
    (if (null? actual.1)
      (null? expected.2)
      (if (not (null? expected.2))
        (if (char=? (car actual.1) (car expected.2))
          (same-characters? (cdr actual.1) (cdr expected.2))
          #f)
        #f))))

(def same-output?
  (lambda (actual expected.1)
    (match actual
      ((initial-output)
        (match expected.1 ((initial-output) #t) ((character-output chars) #f) ((other-output) #f)))
      ((character-output chars.1)
        (match expected.1
          ((initial-output) #f)
          ((character-output wanted) (same-characters? chars.1 wanted))
          ((other-output) #f)))
      ((other-output) #f))))

(def bitwise-not (-> I64 I64) (lambda (x.10) (- (- (ann 0 I64) x.10) (ann 1 I64))))

(def bitwise-and (-> I64 I64 I64)
  (lambda (x.9 y.7)
    (if (= x.9 (ann 0 I64))
      (ann 0 I64)
      (if (= y.7 (ann 0 I64))
        (ann 0 I64)
        (if (= x.9 (ann -1 I64))
          y.7
          (if (= y.7 (ann -1 I64))
            x.9
            ((lambda (z) (if (if (maze-odd? x.9) (maze-odd? y.7) #f) (+ (+ z z) (ann 1 I64)) (+ z z)))
              (bitwise-and (div x.9 (ann 2 I64)) (div y.7 (ann 2 I64))))))))))

(def div (-> I64 I64 I64)
  (lambda (x.8 y.6)
    (if (if (maze-exact-integer? x.8) (if (maze-exact-integer? y.6) (>= x.8 (ann 0 I64)) #f) #f)
      (quotient x.8 y.6)
      (if (< y.6 (ann 0 I64))
        ((lambda (q.3) ((lambda (r.12) ((lambda () (if (= r.12 (ann 0 I64)) q.3 (+ q.3 (ann 1 I64)))))) (- x.8 (* q.3 y.6))))
          (quotient x.8 y.6))
        ((lambda (q.2) ((lambda (r.11) ((lambda () (if (= r.11 (ann 0 I64)) q.2 (- q.2 (ann 1 I64)))))) (- x.8 (* q.2 y.6))))
          (quotient x.8 y.6))))))

(def mod (-> I64 I64 I64)
  (lambda (x.7 y.5)
    (if (if (maze-exact-integer? x.7) (if (maze-exact-integer? y.5) (>= x.7 (ann 0 I64)) #f) #f)
      (remainder x.7 y.5)
      (if (< y.5 (ann 0 I64))
        ((lambda (q.1) ((lambda (r.10) ((lambda () (if (= r.10 (ann 0 I64)) (ann 0 I64) (- r.10 y.5))))) (- x.7 (* q.1 y.5))))
          (quotient x.7 y.5))
        ((lambda (q) ((lambda (r.9) ((lambda () (if (= r.9 (ann 0 I64)) (ann 0 I64) (+ r.9 y.5))))) (- x.7 (* q y.5))))
          (quotient x.7 y.5))))))

(def random-state (-> I64 (Ref I64)) (lambda (n.4) (ref n.4)))

(def rand (-> (Ref I64) I64)
  (lambda (state.1)
    ((lambda (seed A M Q R) ((lambda (hi) ((lambda (lo) ((lambda (test) ((lambda (val.1) ((lambda () (begin (ref-set! state.1 val.1) val.1)))) (if (> test (ann 0 I64)) test (+ test M)))) (- (* A lo) (* R hi)))) (mod seed Q))) (div seed Q)))
      (ref-get state.1)
      (ann 2813 I64)
      (ann 8388607 I64)
      (ann 2787 I64)
      (ann 2699 I64))))

(def random-int (-> I64 (Ref I64) I64) (lambda (n.3 state) (mod (rand state) n.3)))

(def base-set (-> I64 Reachable) (lambda (nelts) (reachable-record (ref nelts) (ref (absent)))))

(def get-set-root (-> Reachable Reachable)
  (lambda (s.1)
    (((lambda () (begin (def lp.4 (lambda (r.8) ((lambda (next.1) (if (present? next.1) (lp.4 (optional-value next.1)) (begin (if (not (same-set? r.8 s.1)) (((lambda () (begin (def lp.5 (lambda (x.6) ((lambda (next) (if (not (same-set-next? r.8 next)) (begin (ref-set! (reachable-next x.6) (present r.8)) (lp.5 (optional-value next))) (unit))) (ref-get (reachable-next x.6))))) lp.5))) s.1) (unit)) r.8))) (ref-get (reachable-next r.8))))) lp.4)))
      s.1)))

(def set-equal? (lambda (s1.1 s2.1) (same-set? (get-set-root s1.1) (get-set-root s2.1))))

(def set-size (lambda (s) (ref-get (reachable-size (get-set-root s)))))

(def union! (-> Reachable Reachable Unit)
  (lambda (s1 s2)
    ((lambda (r1) ((lambda (r2) ((lambda (n1) ((lambda (n2) ((lambda (n.2) ((lambda () (if (> n1 n2) (begin (ref-set! (reachable-next r2) (present r1)) (ref-set! (reachable-size r1) n.2)) (begin (ref-set! (reachable-next r1) (present r2)) (ref-set! (reachable-size r2) n.2)))))) (+ n1 n2))) (set-size r2))) (set-size r1))) (get-set-root s2)))
      (get-set-root s1))))

(def make-wall
  (lambda (owner neighbor bit.1) (wall-record (ref owner) (ref neighbor) (ref bit.1))))

(def wall:owner (lambda (o.22) (ref-get (wall-owner-field o.22))))

(def set-wall:owner (lambda (o.21 v.13) (ref-set! (wall-owner-field o.21) v.13)))

(def wall:neighbor (lambda (o.20) (ref-get (wall-neighbor-field o.20))))

(def set-wall:neighbor (lambda (o.19 v.12) (ref-set! (wall-neighbor-field o.19) v.12)))

(def wall:bit (lambda (o.18) (ref-get (wall-bit-field o.18))))

(def set-wall:bit (lambda (o.17 v.11) (ref-set! (wall-bit-field o.17) v.11)))

(def make-cell
  (lambda (reachable id.1)
    (cell-record (ref reachable) (ref id.1) (ref (ann -1 I64)) (ref (absent)) (ref #f))))

(def cell:reachable (lambda (o.16) (ref-get (cell-reachable-field o.16))))

(def set-cell:reachable (lambda (o.15 v.10) (ref-set! (cell-reachable-field o.15) v.10)))

(def cell:id (lambda (o.14) (ref-get (cell-id-field o.14))))

(def set-cell:id (lambda (o.13 v.9) (ref-set! (cell-id-field o.13) v.9)))

(def cell:walls (lambda (o.12) (ref-get (cell-walls-field o.12))))

(def set-cell:walls (lambda (o.11 v.8) (ref-set! (cell-walls-field o.11) v.8)))

(def cell:parent (lambda (o.10) (ref-get (cell-parent-field o.10))))

(def set-cell:parent (lambda (o.9 v.7) (ref-set! (cell-parent-field o.9) v.7)))

(def cell:mark (lambda (o.8) (ref-get (cell-mark-field o.8))))

(def set-cell:mark (lambda (o.7 v.6) (ref-set! (cell-mark-field o.7) v.6)))

(def vector-for-each-rev (All (T) (-> (-> T Unit) (Vector T) Unit))
  (lambda (proc.3 v.5)
    (((lambda () (begin (def lp.3 (lambda (i.2) (if (>= i.2 (ann 0 I64)) (begin (proc.3 (vector-ref v.5 i.2)) (lp.3 (- i.2 (ann 1 I64)))) (unit)))) lp.3)))
      (- (vector-length v.5) (ann 1 I64)))))

(def permute-vec! (All (T) (-> (Vector T) (Ref I64) (Vector T)))
  (lambda (v.4 random-state.1)
    (begin
      (((lambda () (begin (def lp.2 (lambda (i.1) (if (> i.1 (ann 1 I64)) (begin ((lambda (elt-i j.1) (begin (vector-set! v.4 i.1 (vector-ref v.4 j.1)) (vector-set! v.4 j.1 elt-i))) (vector-ref v.4 i.1) (random-int i.1 random-state.1)) (lp.2 (- i.1 (ann 1 I64)))) (unit)))) lp.2)))
        (- (vector-length v.4) (ann 1 I64)))
      v.4)))

(def dig-maze (-> (Vector Wall) I64 Unit)
  (lambda (walls.5 ncells)
    (vector-until-rev
      (lambda (wall)
        ((lambda (c1) ((lambda (set1) ((lambda (c2) ((lambda (set2) ((lambda () (if (not (set-equal? set1 set2)) ((lambda (walls.4 wall-mask) (begin (union! set1 set2) (set-cell:walls c1 (bitwise-and walls.4 wall-mask)) (= (set-size set1) ncells))) (cell:walls c1) (bitwise-not (wall:bit wall))) #f)))) (cell:reachable c2))) (wall:neighbor wall))) (cell:reachable c1)))
          (wall:owner wall)))
      walls.5)))

(def dfs-maze (-> HexArray Cell (-> (-> Cell Unit) HexArray Cell Unit) Unit)
  (lambda (maze root do-children)
    (((lambda () (begin (def search (lambda (node.4 parent) (begin (set-cell:parent node.4 parent) (do-children (lambda (child) (if (not (same-cell-parent? child parent)) (search child (present node.4)) (unit))) maze node.4)))) search)))
      root
      (absent))))

(def reroot-maze (-> Cell Unit)
  (lambda (new-root)
    (((lambda () (begin (def lp.1 (lambda (node.3 new-parent) ((lambda (old-parent) (begin (set-cell:parent node.3 new-parent) (if (present? old-parent) (lp.1 (optional-value old-parent) (present node.3)) (unit)))) (cell:parent node.3)))) lp.1)))
      new-root
      (absent))))

(def path-length (-> Cell I64)
  (lambda (cell.1)
    (((lambda () (begin (def loop.12 (lambda (len node.2) (if (not (present? node.2)) (begin (unit) len) (loop.12 (+ len (ann 1 I64)) (cell:parent (optional-value node.2)))))) loop.12)))
      (ann 0 I64)
      (cell:parent cell.1))))

(def mark-path (-> Cell Unit)
  (lambda (node)
    (((lambda () (begin (def lp (lambda (node.1) (begin (set-cell:mark node.1 #t) ((lambda (value.5) (if (present? value.5) (lp (optional-value value.5)) (unit))) (cell:parent node.1))))) lp)))
      node)))

(def make-harr
  (lambda (nrows.7 ncols.7 elts) (harr-record (ref nrows.7) (ref ncols.7) (ref elts))))

(def harr:nrows (lambda (o.6) (ref-get (harr-rows-field o.6))))

(def set-harr:nrows (lambda (o.5 v.3) (ref-set! (harr-rows-field o.5) v.3)))

(def harr:ncols (lambda (o.4) (ref-get (harr-columns-field o.4))))

(def set-harr:ncols (lambda (o.3 v.2) (ref-set! (harr-columns-field o.3) v.2)))

(def harr:elts (lambda (o.2) (ref-get (harr-elements-field o.2))))

(def set-harr:elts (lambda (o.1 v.1) (ref-set! (harr-elements-field o.1) v.1)))

(def harr
  (lambda (r.7 c.11) (make-harr r.7 c.11 (make-vector (* r.7 c.11) (uninitialized-cell)))))

(def href
  (lambda (ha.2 x.5 y.4)
    ((lambda (r.6 c.10) (vector-ref (harr:elts ha.2) (+ (* (harr:ncols ha.2) r.6) c.10)))
      (div y.4 (ann 2 I64))
      (div x.5 (ann 3 I64)))))

(def hset!
  (lambda (ha.1 x.4 y.3 val)
    ((lambda (r.5 c.9) (vector-set! (harr:elts ha.1) (+ (* (harr:ncols ha.1) r.5) c.9) val))
      (div y.3 (ann 2 I64))
      (div x.4 (ann 3 I64)))))

(def href/rc (lambda (ha r.4 c.8) (vector-ref (harr:elts ha) (+ (* (harr:ncols ha) r.4) c.8))))

(def harr-tabulate (-> I64 I64 (-> I64 I64 Cell) HexArray)
  (lambda (nrows.6 ncols.6 proc.2)
    ((lambda (v) (begin (((lambda () (begin (def loop.10 (lambda (r.3) (if (< r.3 (ann 0 I64)) (unit) (begin (((lambda () (begin (def loop.11 (lambda (c.7 i) (if (= c.7 ncols.6) (unit) (begin (vector-set! v i (proc.2 (* (ann 3 I64) c.7) (+ (* (ann 2 I64) r.3) (bitwise-and c.7 (ann 1 I64))))) (loop.11 (+ c.7 (ann 1 I64)) (+ i (ann 1 I64))))))) loop.11))) (ann 0 I64) (* r.3 ncols.6)) (loop.10 (- r.3 (ann 1 I64))))))) loop.10))) (- nrows.6 (ann 1 I64))) (make-harr nrows.6 ncols.6 v)))
      (make-vector (* nrows.6 ncols.6) (uninitialized-cell)))))

(def harr-for-each (-> (-> Cell Unit) HexArray Unit)
  (lambda (proc.1 harr.6) (vector-for-each-rev proc.1 (harr:elts harr.6))))

(def south-west (ann 1 I64))

(def south (ann 2 I64))

(def south-east (ann 4 I64))

(def gen-maze-array
  (lambda (r.2 c.6)
    (harr-tabulate r.2 c.6 (lambda (x.3 y.2) (make-cell (base-set (ann 1 I64)) (coordinate x.3 y.2))))))

(def make-wall-vec (-> HexArray (Vector Wall))
  (lambda (harr.5)
    ((lambda (nrows.5) ((lambda (ncols.5) ((lambda (xmax) ((lambda (walls.3) ((lambda (add-wall) ((lambda () (begin (((lambda () (begin (def loop.8 (lambda (x.2) (if (< x.2 (ann 0 I64)) (unit) (begin (((lambda () (begin (def loop.9 (lambda (y.1) (if (<= y.1 (ann 1 I64)) (unit) (begin ((lambda (hex) (begin (if (not (maze-zero? x.2)) (add-wall hex (href harr.5 (- x.2 (ann 3 I64)) (- y.1 (ann 1 I64))) south-west) (unit)) (add-wall hex (href harr.5 x.2 (- y.1 (ann 2 I64))) south) (if (< x.2 xmax) (add-wall hex (href harr.5 (+ x.2 (ann 3 I64)) (- y.1 (ann 1 I64))) south-east) (unit)))) (href harr.5 x.2 y.1)) (loop.9 (- y.1 (ann 2 I64))))))) loop.9))) (+ (* (- nrows.5 (ann 1 I64)) (ann 2 I64)) (bitwise-and x.2 (ann 1 I64)))) (loop.8 (- x.2 (ann 3 I64))))))) loop.8))) (* (- ncols.5 (ann 1 I64)) (ann 3 I64))) (if (> ncols.5 (ann 1 I64)) ((lambda (rmoc-x) (begin ((lambda (rmoc-hex) (begin (if (< rmoc-x xmax) (add-wall rmoc-hex (href harr.5 xmax (ann 0 I64)) south-east) (unit)) (add-wall rmoc-hex (href harr.5 (- rmoc-x (ann 3 I64)) (ann 0 I64)) south-west))) (href harr.5 rmoc-x (ann 1 I64))) (((lambda () (begin (def loop.7 (lambda (x.1) (if (< x.1 (ann 3 I64)) (unit) (begin (add-wall (href harr.5 x.1 (ann 1 I64)) (href harr.5 (- x.1 (ann 3 I64)) (ann 0 I64)) south-west) (add-wall (href harr.5 x.1 (ann 1 I64)) (href harr.5 (+ x.1 (ann 3 I64)) (ann 0 I64)) south-east) (loop.7 (- x.1 (ann 6 I64))))))) loop.7))) (- rmoc-x (ann 6 I64))))) (+ (ann 3 I64) (* (ann 6 I64) (div (- ncols.5 (ann 2 I64)) (ann 2 I64))))) (unit)) (list->vector (ref-get walls.3)))))) (lambda (o n.1 b) (ref-set! walls.3 (cons (make-wall o n.1 b) (ref-get walls.3)))))) (ref (ann (empty-list ) (List Wall))))) (* (ann 3 I64) (- ncols.5 (ann 1 I64))))) (harr:ncols harr.5)))
      (harr:nrows harr.5))))

(def pick-entrances (-> HexArray Entrances)
  (lambda (harr.4)
    (begin
      (dfs-maze harr.4 (href/rc harr.4 (ann 0 I64) (ann 0 I64)) for-each-hex-child)
      ((lambda (nrows.4 ncols.4) (((lambda () (begin (def tp-lp (lambda (max-len entrance.3 exit.2 tcol) (if (< tcol (ann 0 I64)) (entrances entrance.3 exit.2) ((lambda (top-cell) (begin (reroot-maze top-cell) ((lambda (result.4) ((lambda (max-len.2 entrance.5 exit.4) (tp-lp max-len.2 entrance.5 exit.4 (- tcol (ann 1 I64)))) (longest-length result.4) (longest-top result.4) (longest-bottom result.4))) (((lambda () (begin (def bt-lp (lambda (max-len.1 entrance.4 exit.3 bcol) (if (< bcol (ann 0 I64)) (longest-path max-len.1 entrance.4 exit.3) ((lambda (this-len) (if (> this-len max-len.1) (bt-lp this-len (present tcol) (present bcol) (- bcol (ann 1 I64))) (bt-lp max-len.1 entrance.4 exit.3 (- bcol (ann 1 I64))))) (path-length (href/rc harr.4 (ann 0 I64) bcol)))))) bt-lp))) max-len entrance.3 exit.2 (- ncols.4 (ann 1 I64)))))) (href/rc harr.4 (- nrows.4 (ann 1 I64)) tcol))))) tp-lp))) (ann -1 I64) (absent) (absent) (- ncols.4 (ann 1 I64))))
        (harr:nrows harr.4)
        (harr:ncols harr.4)))))

(def for-each-hex-child (-> (-> Cell Unit) HexArray Cell Unit)
  (lambda (proc harr.3 cell)
    ((lambda (walls.2) ((lambda (id) ((lambda (x) ((lambda (y) ((lambda (nr) ((lambda (nc) ((lambda (maxy) ((lambda (maxx) ((lambda () (begin (if (not (bit-test walls.2 south-west)) (proc (href harr.3 (- x (ann 3 I64)) (- y (ann 1 I64)))) (unit)) (if (not (bit-test walls.2 south)) (proc (href harr.3 x (- y (ann 2 I64)))) (unit)) (if (not (bit-test walls.2 south-east)) (proc (href harr.3 (+ x (ann 3 I64)) (- y (ann 1 I64)))) (unit)) (if (if (> x (ann 0 I64)) ((lambda (value.4) (if value.4 value.4 (maze-zero? (mod x (ann 6 I64))))) (<= y maxy)) #f) ((lambda (nw) (if (not (bit-test (cell:walls nw) south-east)) (proc nw) (unit))) (href harr.3 (- x (ann 3 I64)) (+ y (ann 1 I64)))) (unit)) (if (< y maxy) ((lambda (n) (if (not (bit-test (cell:walls n) south)) (proc n) (unit))) (href harr.3 x (+ y (ann 2 I64)))) (unit)) (if (if (< x maxx) ((lambda (value.3) (if value.3 value.3 (maze-zero? (mod x (ann 6 I64))))) (<= y maxy)) #f) ((lambda (ne) (if (not (bit-test (cell:walls ne) south-west)) (proc ne) (unit))) (href harr.3 (+ x (ann 3 I64)) (+ y (ann 1 I64)))) (unit)))))) (* (ann 3 I64) (- nc (ann 1 I64))))) (* (ann 2 I64) (- nr (ann 1 I64))))) (harr:ncols harr.3))) (harr:nrows harr.3))) (coordinate-y id))) (coordinate-x id))) (cell:id cell)))
      (cell:walls cell))))

(def make-maze (-> I64 I64 Maze)
  (lambda (nrows.3 ncols.3)
    ((lambda (cells.1) ((lambda (walls.1) ((lambda () (begin (dig-maze walls.1 (* nrows.3 ncols.3)) ((lambda (result.3) ((lambda (entrance.2 exit.1) ((lambda (exit-cell) ((lambda (walls) ((lambda () (begin (reroot-maze (href/rc cells.1 (- nrows.3 (ann 1 I64)) entrance.2)) (mark-path exit-cell) (set-cell:walls exit-cell (bitwise-and walls (bitwise-not south))) (maze-result cells.1 entrance.2 exit.1))))) (cell:walls exit-cell))) (href/rc cells.1 (ann 0 I64) exit.1))) (optional-value (entrance-top result.3)) (optional-value (entrance-bottom result.3)))) (pick-entrances cells.1)))))) (permute-vec! (make-wall-vec cells.1) (random-state (ann 20 I64)))))
      (gen-maze-array nrows.3 ncols.3))))

(def pmaze (-> I64 I64 Unit)
  (lambda (nrows.2 ncols.2)
    ((lambda (result.2) ((lambda (cells entrance.1 exit) (print-hexmaze cells entrance.1)) (maze-cells result.2) (maze-entrance result.2) (maze-exit result.2)))
      (make-maze nrows.2 ncols.2))))

(def output (ref (ann (empty-list ) (List Char))))

(def write-ch (lambda (c.5) (ref-set! output (cons c.5 (ref-get output)))))

(def print-hexmaze (-> HexArray I64 Unit)
  (lambda (harr.2 entrance)
    ((lambda (nrows.1) ((lambda (ncols.1) ((lambda (ncols2) ((lambda () (begin (((lambda () (begin (def loop.6 (lambda (c.4) (if (>= c.4 ncols.1) (unit) (begin (write-ch #\space) (write-ch #\space) (write-ch #\space) (write-ch (if (= c.4 entrance) #\space #\_)) (loop.6 (+ c.4 (ann 2 I64))))))) loop.6))) (ann 1 I64)) (write-ch #\newline) (write-ch #\space) (((lambda () (begin (def loop.5 (lambda (c.3) (if (>= c.3 ncols2) (unit) (begin (write-ch (if (= c.3 entrance) #\space #\_)) (write-ch #\/) (write-ch (dot/space harr.2 (- nrows.1 (ann 1 I64)) (+ c.3 (ann 1 I64)))) (write-ch #\\) (loop.5 (+ c.3 (ann 2 I64))))))) loop.5))) (ann 0 I64)) (if (maze-odd? ncols.1) (write-ch (if (= entrance (- ncols.1 (ann 1 I64))) #\space #\_)) (unit)) (write-ch #\newline) (((lambda () (begin (def loop.2 (lambda (r.1) (if (< r.1 (ann 0 I64)) (unit) (begin (write-ch #\/) (((lambda () (begin (def loop.4 (lambda (c.2) (if (>= c.2 ncols2) (unit) (begin (write-ch (dot/space harr.2 r.1 (- c.2 (ann 1 I64)))) (display-hexbottom (cell:walls (href/rc harr.2 r.1 c.2))) (loop.4 (+ c.2 (ann 2 I64))))))) loop.4))) (ann 1 I64)) (if (maze-odd? ncols.1) (begin (write-ch (dot/space harr.2 r.1 (- ncols.1 (ann 1 I64)))) (write-ch #\\)) (unit)) (write-ch #\newline) (((lambda () (begin (def loop.3 (lambda (c.1) (if (>= c.1 ncols2) (unit) (begin (display-hexbottom (cell:walls (href/rc harr.2 r.1 c.1))) (write-ch (dot/space harr.2 (- r.1 (ann 1 I64)) (+ c.1 (ann 1 I64)))) (loop.3 (+ c.1 (ann 2 I64))))))) loop.3))) (ann 0 I64)) (if (maze-odd? ncols.1) (display-hexbottom (cell:walls (href/rc harr.2 r.1 (- ncols.1 (ann 1 I64))))) (if (not (maze-zero? r.1)) (write-ch #\\) (unit))) (write-ch #\newline) (loop.2 (- r.1 (ann 1 I64))))))) loop.2))) (- nrows.1 (ann 1 I64))))))) (* (ann 2 I64) (div ncols.1 (ann 2 I64))))) (harr:ncols harr.2)))
      (harr:nrows harr.2))))

(def bit-test (lambda (j bit) (not (maze-zero? (bitwise-and j bit)))))

(def dot/space
  (lambda (harr.1 r c) (if (if (>= r (ann 0 I64)) (cell:mark (href/rc harr.1 r c)) #f) #\. #\space)))

(def display-hexbottom
  (lambda (hexwalls)
    (begin
      (write-ch (if (bit-test hexwalls south-west) #\\ #\space))
      (write-ch (if (bit-test hexwalls south) #\_ #\space))
      (write-ch (if (bit-test hexwalls south-east) #\/ #\space)))))

(def run (-> I64 I64 (List Char))
  (lambda (nrows ncols)
    (begin (ref-set! output (empty-list )) (pmaze nrows ncols) (maze-reverse (ref-get output)))))

(def Specification (datatype ()
  (specification
    (count I64 specification-count)
    (rows I64 specification-rows)
    (columns I64 specification-columns)
    (expected Output specification-expected))))

(def maze-input-integer
  (lambda (value.2)
    (match (datum-number-value value.2)
      ((exact-number number) number)
      ((rational-number number.1) (datum-fail "Maze requires exact integers"))
      ((inexact-number number.2) (datum-fail "Maze requires exact integers"))
      ((complex-number real imaginary) (datum-fail "Maze requires exact integers")))))

(def maze-input-output
  (lambda (value.1)
    (if (if (= (datum-kind value.1) (ann 1 I64)) (not (datum-boolean-value value.1)) #f)
      (initial-output)
      (((lambda () (begin (def loop.1 (lambda (tail result.1) (if (datum-null? tail) (character-output (maze-reverse result.1)) (if (if (datum-pair? tail) (= (datum-kind (datum-car tail)) (ann 2 I64)) #f) (loop.1 (datum-cdr tail) (cons (datum-character-value (datum-car tail)) result.1)) (other-output))))) loop.1)))
        value.1
        (ann (empty-list ) (List Char))))))

(def read-specification
  (lambda (port)
    ((lambda (count.2) ((lambda (rows) ((lambda (columns) ((lambda (expected) ((lambda () (specification count.2 rows columns expected)))) (maze-input-output (read-value! (read port))))) (maze-input-integer (read-value! (read port))))) (maze-input-integer (read-value! (read port)))))
      (maze-input-integer (read-value! (read port))))))

(def configured (call-with-input-file "input.txt" read-specification))

(def configured-count (-> I64) (lambda () (specification-count configured)))

(define-extern barrier "benchmark" "barrier" (-> Bool))

(def hide (All (T) (-> I64 T T)) (lambda (count.1 value) (if (barrier) value (unreachable))))

(def bench (-> I64 I64)
  (lambda (count)
    (((lambda () (begin (def loop (lambda (index result) (if (< index count) (loop (+ index (ann 1 I64)) (character-output (run (hide count (specification-rows configured)) (hide count (specification-columns configured))))) (if (same-output? result (specification-expected configured)) (ann 1 I64) (ann 0 I64))))) loop)))
      (ann 0 I64)
      (initial-output))))

(unit)
