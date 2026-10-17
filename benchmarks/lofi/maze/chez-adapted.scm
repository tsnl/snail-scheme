(import
  (only (chezscheme)
    current-time
    machine-type
    scheme-version-number
    time-nanosecond
    time-second)
  (except
    (rename (rnrs) (define-record-type r6rs:define-record-type))
    bitwise-and
    bitwise-not
    div
    mod
    partition)
  (rnrs mutable-pairs)
  (rnrs mutable-strings)
  (rnrs r5rs))

(define-syntax define-record-type
  ;; Simplistic R7RS to R6RS define-record-type transformation.
  (syntax-rules ()
    ((define-record-type name
      (make-name param ...)
      name?
      (field-name field-ref field-set!)
      ...)
     (r6rs:define-record-type (name make-name name?)
       (protocol
         (lambda (new)
           (lambda (param ...)
             (new param ...))))
       (fields
         (mutable field-name field-ref field-set!)
         ...)))))

(define (exact-integer? z)
  (and (exact? z) (integer? z)))

 (define read-line
   get-line)

(define (square x)
  (* x x))

(define write-string
  (case-lambda
    ((string)
      (put-string (current-output-port) string))
    ((string port)
      (put-string port string))
    ((string port start)
      (put-string port string start))
    ((string port start end)
      (put-string port string start (fx+ (fx- end start) 1)))))
;; R7RS benchmark timing for compiled Chez programs. The upstream Petite-Chez
;; prelude supplies language compatibility; the benchmark body is unchanged.
;; Use Chez's monotonic clock and integer nanoseconds, not two wall-clock reads.

(define (current-jiffy)
  (let ((now (current-time 'time-monotonic)))
    (+ (* (time-second now) 1000000000) (time-nanosecond now))))

(define (jiffies-per-second) 1000000000)

(define (current-second)
  (/ (current-jiffy) 1000000000.0))

(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define-syntax define-overload (syntax-rules () ((_ . declaration) (begin))))
(define-syntax define-data
  (lambda (form)
    (syntax-case form ()
      ((context name variant ...)
       (datum->syntax #'context
         (cons 'begin
           (apply append
             (map (lambda (variant)
                    (let ((tag (car variant)) (fields (cdr variant)))
                      (cons `(define (,tag ,@(map car fields)) (vector ',tag ,@(map car fields)))
                        (let loop ((fields fields) (index 1))
                          (if (null? fields) '()
                              (append
                                (if (= (length (car fields)) 3)
                                    `((define (,(caddar fields) value)
                                        (unless (eq? (vector-ref value 0) ',tag)
                                          (error ',tag "wrong typed variant" value))
                                        (vector-ref value ,index))) '())
                                (loop (cdr fields) (+ index 1))))))))
                  (syntax->datum #'(variant ...))))))))))
(define-syntax match
  (lambda (form)
    (syntax-case form ()
      ((context value arm ...)
       (let ((temporary (syntax->datum (car (generate-temporaries #'(value))))))
         (datum->syntax #'context
           `(let ((,temporary ,(syntax->datum #'value)))
              (cond
                ,@(map (lambda (arm)
                         (let ((pattern (car arm)))
                           `((eq? (vector-ref ,temporary 0) ',(car pattern))
                             (let ,(let loop ((names (cdr pattern)) (index 1))
                                     (if (null? names) '()
                                         (cons `(,(car names) (vector-ref ,temporary ,index))
                                           (loop (cdr names) (+ index 1)))))
                               ,@(cdr arm)))))
                       (syntax->datum #'(arm ...)))
                (else (error 'match "invalid typed variant" ,temporary))))))))))
(define (unit) (if #f #f))
(define (unreachable) (error 'reader "unreachable typed branch"))
(define (ref value) (vector value))
(define (ref-get value) (vector-ref value 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define ref-eq? eq?)
(define vector-eq? eq?)
(define string-eq? eq?)
(define bytevector-eq? eq?)
(define i32-eq eqv?)
(define i32->i64 values)
(define i64->i32 values)
(define i64->f64 inexact)
(define (f64->i64 value)
  (unless (and (finite? value) (<= -9223372036854775808.0 value) (< value 9223372036854775808.0))
    (error 'f64->i64 "out of range" value))
  (exact (truncate value)))
(define (empty-vector) (vector))
;; The identical Datum body hashes complete wrapping I64 words. Chez's generic
;; integers do not wrap, so these scalar adapters make that boundary explicit.
(define (i64-word value)
  (let ((bits (bitwise-bit-field value 0 64)))
    (if (< bits 9223372036854775808) bits (- bits 18446744073709551616))))
(define (i64-add a b) (i64-word (+ a b)))
(define (i64-mul a b) (i64-word (* a b)))
(define (i64-bitwise-and a b) (bitwise-if a b 0))
(define i64-bitwise-xor bitwise-xor)
(define (i64-shift-right/logical value count)
  (i64-word (bitwise-arithmetic-shift-right (bitwise-bit-field value 0 64)
                                          (bitwise-bit-field count 0 6))))
(define (string-copy! target at source start end)
  (do ((index start (+ index 1))) ((= index end))
    (string-set! target (+ at (- index start)) (string-ref source index))))
(define (vector-copy! target at source start end)
  (let ((count (- end start)))
    (if (and (eq? target source) (> at start))
        (do ((index (- count 1) (- index 1))) ((< index 0))
          (vector-set! target (+ at index) (vector-ref source (+ start index))))
        (do ((index 0 (+ index 1))) ((= index count))
          (vector-set! target (+ at index) (vector-ref source (+ start index)))))))
(define-data Optional (absent) (present (value T optional-value)))
(define-data Reachable
  (reachable-record (size (Ref I64) reachable-size)
                    (next (Ref (Optional Reachable)) reachable-next)))
(define-data Coordinate (coordinate (x I64 coordinate-x) (y I64 coordinate-y)))
(define-data Cell
  (uninitialized-cell)
  (cell-record (reachable (Ref Reachable) cell-reachable-field)
               (id (Ref Coordinate) cell-id-field)
               (walls (Ref I64) cell-walls-field)
               (parent (Ref (Optional Cell)) cell-parent-field)
               (mark (Ref Bool) cell-mark-field)))
(define-data Wall
  (wall-record (owner (Ref Cell) wall-owner-field)
               (neighbor (Ref Cell) wall-neighbor-field)
               (bit (Ref I64) wall-bit-field)))
(define-data HexArray
  (harr-record (rows (Ref I64) harr-rows-field)
               (columns (Ref I64) harr-columns-field)
               (elements (Ref (Vector Cell)) harr-elements-field)))
(define-data Entrances
  (entrances (top (Optional I64) entrance-top) (bottom (Optional I64) entrance-bottom)))
(define-data LongestPath
  (longest-path (length I64 longest-length)
                (top (Optional I64) longest-top) (bottom (Optional I64) longest-bottom)))
(define-data Maze
  (maze-result (cells HexArray maze-cells) (entrance I64 maze-entrance) (exit I64 maze-exit)))
(define-data Output
  (initial-output) (character-output (characters (List Char) output-characters)) (other-output))
(: present? (All (T) (-> (Optional T) Bool)))
(define (present? value) (match value ((absent) #f) ((present item) #t)))
(define (same-set? left right) (ref-eq? (reachable-size left) (reachable-size right)))
(define (same-set-next? left next)
  (and (present? next) (same-set? left (optional-value next))))
;; A fresh field Ref supplies stable identity even if that field is mutated.
(define (same-cell? left right) (ref-eq? (cell-walls-field left) (cell-walls-field right)))
(define (same-cell-parent? cell parent)
  (and (present? parent) (same-cell? cell (optional-value parent))))
(define (maze-zero? value) (= value 0))
(define (maze-odd? value) (not (= (remainder value 2) 0)))
(: maze-exact-integer? (-> I64 Bool))
(define (maze-exact-integer? value) #t)
(: maze-reverse (All (T) (-> (List T) (List T))))
(define (maze-reverse values)
  (let loop ((values values) (result '()))
    (if (null? values) result (loop (cdr values) (cons (car values) result)))))
;; This is only the source's immediate lexical escape: stop before the next
;; vector lookup or index update. No continuation escapes or can be resumed.
(: vector-until-rev (All (T) (-> (-> T Bool) (Vector T) Unit)))
(define (vector-until-rev procedure values)
  (let loop ((index (- (vector-length values) 1)))
    (when (>= index 0)
      (unless (procedure (vector-ref values index)) (loop (- index 1))))))
(define (same-characters? actual expected)
  (if (null? actual) (null? expected)
      (and (not (null? expected)) (char=? (car actual) (car expected))
           (same-characters? (cdr actual) (cdr expected)))))
(define (same-output? actual expected)
  (match actual
    ((initial-output) (match expected ((initial-output) #t)
      ((character-output chars) #f) ((other-output) #f)))
    ((character-output chars) (match expected ((initial-output) #f)
      ((character-output wanted) (same-characters? chars wanted)) ((other-output) #f)))
    ((other-output) #f)))
(define-syntax maze-cond
  (syntax-rules (else =>)
    ((_) (unit))
    ((_ (else body ...)) (begin body ...))
    ((_ (test => procedure) rest ...)
     (let ((value test))
       (if (present? value) (procedure (optional-value value)) (maze-cond rest ...))))
    ((_ (test body ...) rest ...) (if test (begin body ...) (maze-cond rest ...)))))
(define-syntax maze-step
  (syntax-rules () ((_ variable) variable) ((_ variable step) step)))
(define-syntax maze-do
  (syntax-rules ()
    ((_ ((variable initial step ...) ...) (test result ...) body ...)
     (let loop ((variable initial) ...)
       (if test (begin (unit) result ...)
           (begin body ... (loop (maze-step variable step ...) ...)))))))
(define (chez-output value)
  (cond ((eq? value #f) (initial-output))
        ((and (list? value) (for-all char? value)) (character-output value))
        (else (other-output))))
(define (original-output value)
  (match value ((initial-output) #f) ((character-output chars) chars) ((other-output) #t)))
(: bitwise-not (-> I64 I64))
(: bitwise-and (-> I64 I64 I64))
(: div (-> I64 I64 I64))
(: mod (-> I64 I64 I64))
(: random-state (-> I64 (Ref I64)))
(: rand (-> (Ref I64) I64))
(: random-int (-> I64 (Ref I64) I64))
(: base-set (-> I64 Reachable))
(: get-set-root (-> Reachable Reachable))
(: union! (-> Reachable Reachable Unit))
(: vector-for-each-rev (All (T) (-> (-> T Unit) (Vector T) Unit)))
(: permute-vec! (All (T) (-> (Vector T) (Ref I64) (Vector T))))
(: dig-maze (-> (Vector Wall) I64 Unit))
(: dfs-maze (-> HexArray Cell (-> (-> Cell Unit) HexArray Cell Unit) Unit))
(: reroot-maze (-> Cell Unit))
(: path-length (-> Cell I64))
(: mark-path (-> Cell Unit))
(: harr-tabulate (-> I64 I64 (-> I64 I64 Cell) HexArray))
(: harr-for-each (-> (-> Cell Unit) HexArray Unit))
(: for-each-hex-child (-> (-> Cell Unit) HexArray Cell Unit))
(: make-wall-vec (-> HexArray (Vector Wall)))
(: pick-entrances (-> HexArray Entrances))
(: make-maze (-> I64 I64 Maze))
(: pmaze (-> I64 I64 Unit))
(: print-hexmaze (-> HexArray I64 Unit))
(: run (-> I64 I64 (List Char)))
;;; MAZE -- Constructs a maze on a hexagonal grid, written by Olin Shivers.


;;; R6RS procedures needed by this benchmark.

(define (bitwise-not x)
  (- (- 0 x) 1))

(define (bitwise-and x y);; two arguments are enough for this benchmark
  (maze-cond ((= x 0) 0)
        ((= y 0) 0)
        ((= x -1) y)
        ((= y -1) x)
        (else
         (let ((z (bitwise-and (div x 2) (div y 2))))
           (if (and (maze-odd? x) (maze-odd? y))
               (+ (+ z z) 1)
               (+ z z))))))

(define (div x y)
  (maze-cond ((and (maze-exact-integer? x)
              (maze-exact-integer? y)
              (>= x 0))
         (quotient x y))
        ((< y 0)
         ;; x < 0, y < 0
         (let* ((q (quotient x y))
                (r (- x (* q y))))
           (if (= r 0)
               q
               (+ q 1))))
        (else
         ;; x < 0, y > 0
         (let* ((q (quotient x y))
                (r (- x (* q y))))
           (if (= r 0)
               q
               (- q 1))))))

(define (mod x y)
  (maze-cond ((and (maze-exact-integer? x)
              (maze-exact-integer? y)
              (>= x 0))
         (remainder x y))
        ((< y 0)
         ;; x < 0, y < 0
         (let* ((q (quotient x y))
                (r (- x (* q y))))
           (if (= r 0)
               0
               (- r y))))
        (else
         ;; x < 0, y > 0
         (let* ((q (quotient x y))
                (r (- x (* q y))))
           (if (= r 0)
               0
               (+ r y))))))

;;; End of R6RS procedures.

;;------------------------------------------------------------------------------
;; Was file "rand.scm".

;; Minimal Standard Random Number Generator
;; Park & Miller, CACM 31(10), Oct 1988, 32 bit integer version.
;; better constants, as proposed by Park.
;; By Ozan Yigit

;;; Rehacked by Olin 4/1995.

(define (random-state n)
  (ref n))

(define (rand state)
  (let ((seed (ref-get state))
        (A 2813);; 48271
        (M 8388607);; 2147483647
        (Q 2787);; 44488
        (R 2699));; 3399
    (let* ((hi (div seed Q))
           (lo (mod seed Q))
           (test (- (* A lo) (* R hi)))
           (val (if (> test 0) test (+ test M))))
      (ref-set! state val)
      val)))

(define (random-int n state)
  (mod (rand state) n))

;; poker test
;; seed 1
;; cards 0-9 inclusive (random 10)
;; five cards per hand
;; 10000 hands
;;
;; Poker Hand     Example    Probability  Calculated
;; 5 of a kind    (aaaaa)      0.0001      0
;; 4 of a kind    (aaaab)      0.0045      0.0053
;; Full house     (aaabb)      0.009       0.0093
;; 3 of a kind    (aaabc)      0.072       0.0682
;; two pairs      (aabbc)      0.108       0.1104
;; Pair           (aabcd)      0.504       0.501
;; Bust           (abcde)      0.3024      0.3058

;; (define (random n)
;;   (let* ((M 2147483647)
;;        (slop (modulo M n)))
;;     (let loop ((r (rand)))
;;       (if (> r slop)
;;         (modulo r n)
;;         (loop (rand))))))
;;
;; (define (rngtest)
;;   (display "implementation ")
;;   (srand 1)
;;   (let loop ((n 0))
;;     (if (< n 10000)
;;         (begin
;;          (rand)
;;          (loop (1+ n)))))
;;   (if (= *seed* 399268537)
;;       (display "looks correct.")
;;       (begin
;;        (display "failed.")
;;        (newline)
;;        (display "   current seed ") (display *seed*)
;;        (newline)
;;        (display "   correct seed 399268537")))
;;   (newline))

;;------------------------------------------------------------------------------
;; Was file "uf.scm".

;;; Tarjan's amortised union-find data structure.
;;; Copyright (c) 1995 by Olin Shivers.

;;; This data structure implements disjoint sets of elements.
;;; Four operations are supported. The implementation is extremely
;;; fast -- any sequence of N operations can be performed in time
;;; so close to linear it's laughable how close it is. See your
;;; intro data structures book for more. The operations are:
;;;
;;; - (base-set nelts) -> set
;;;   Returns a new set, of size NELTS.
;;;
;;; - (set-size s) -> integer
;;;   Returns the number of elements in set S.
;;;
;;; - (union! set1 set2)
;;;   Unions the two sets -- SET1 and SET2 are now considered the same set
;;;   by SET-EQUAL?.
;;;
;;; - (set-equal? set1 set2)
;;;   Returns true <==> the two sets are the same.

;;; Representation: a set is a cons cell. Every set has a "representative"
;;; cons cell, reached by chasing cdr links until we find the cons with
;;; cdr = (). Set equality is determined by comparing representatives using
;;; EQ?. A representative's car contains the number of elements in the set.

;;; The speed of the algorithm comes because when we chase links to find
;;; representatives, we collapse links by changing all the cells in the path
;;; we followed to point directly to the representative, so that next time
;;; we walk the cdr-chain, we'll go directly to the representative in one hop.


(define (base-set nelts) (reachable-record (ref nelts) (ref (absent))))

;;; Sets are chained together through cdr links. Last guy in the chain
;;; is the root of the set.

(define (get-set-root s)
  (let lp ((r s));; Find the last pair
    (let ((next (ref-get (reachable-next r))));; in the list. That's
      (maze-cond ((present? next) (lp (optional-value next)));; the root r.

            (else
             (if (not (same-set? r s));; Now zip down the list again,
                 (let lp ((x s));; changing everyone's cdr to r.
                   (let ((next (ref-get (reachable-next x))))
                     (maze-cond ((not (same-set-next? r next))
                            (ref-set! (reachable-next x) (present r))
                            (lp (optional-value next)))))))
             r)))));; Then return r.

(define (set-equal? s1 s2) (same-set? (get-set-root s1) (get-set-root s2)))

(define (set-size s) (ref-get (reachable-size (get-set-root s))))

(define (union! s1 s2)
  (let* ((r1 (get-set-root s1))
         (r2 (get-set-root s2))
         (n1 (set-size r1))
         (n2 (set-size r2))
         (n  (+ n1 n2)))

    (maze-cond ((> n1 n2)
           (ref-set! (reachable-next r2) (present r1))
           (ref-set! (reachable-size r1) n))
          (else
           (ref-set! (reachable-next r1) (present r2))
           (ref-set! (reachable-size r2) n)))))

;;------------------------------------------------------------------------------
;; Was file "maze.scm".

;;; Building mazes with union/find disjoint sets.
;;; Copyright (c) 1995 by Olin Shivers.

;;; This is the algorithmic core of the maze constructor.
;;; External dependencies:
;;; - RANDOM-INT
;;; - Union/find code
;;; - bitwise logical functions

;; (define-record wall
;;   owner;; Cell that owns this wall.
;;   neighbor;; The other cell bordering this wall.
;;   bit);; Integer -- a bit identifying this wall in OWNER's cell.

;; (define-record cell
;;   reachable;; Union/find set -- all reachable cells.
;;   id;; Identifying info (e.g., the coords of the cell).
;;   (walls -1);; A bitset telling which walls are still standing.
;;   (parent #f);; For DFS spanning tree construction.
;;   (mark #f));; For marking the solution path.

(define (make-wall owner neighbor bit)
  (wall-record (ref owner) (ref neighbor) (ref bit)))

(define (wall:owner o)          (ref-get (wall-owner-field o)))
(define (set-wall:owner o v)    (ref-set! (wall-owner-field o) v))
(define (wall:neighbor o)       (ref-get (wall-neighbor-field o)))
(define (set-wall:neighbor o v) (ref-set! (wall-neighbor-field o) v))
(define (wall:bit o)            (ref-get (wall-bit-field o)))
(define (set-wall:bit o v)      (ref-set! (wall-bit-field o) v))

(define (make-cell reachable id)
  (cell-record (ref reachable) (ref id) (ref -1) (ref (absent)) (ref #f)))

(define (cell:reachable o)       (ref-get (cell-reachable-field o)))
(define (set-cell:reachable o v) (ref-set! (cell-reachable-field o) v))
(define (cell:id o)              (ref-get (cell-id-field o)))
(define (set-cell:id o v)        (ref-set! (cell-id-field o) v))
(define (cell:walls o)           (ref-get (cell-walls-field o)))
(define (set-cell:walls o v)     (ref-set! (cell-walls-field o) v))
(define (cell:parent o)          (ref-get (cell-parent-field o)))
(define (set-cell:parent o v)    (ref-set! (cell-parent-field o) v))
(define (cell:mark o)            (ref-get (cell-mark-field o)))
(define (set-cell:mark o v)      (ref-set! (cell-mark-field o) v))

;;; Iterates in reverse order.

(define (vector-for-each-rev proc v)
  (let lp ((i (- (vector-length v) 1)))
    (maze-cond ((>= i 0)
           (proc (vector-ref v i))
           (lp (- i 1))))))

;;; Randomly permute a vector.

(define (permute-vec! v random-state)
  (let lp ((i (- (vector-length v) 1)))
    (maze-cond ((> i 1)
           (let ((elt-i (vector-ref v i))
                 (j (random-int i random-state)));; j in [0,i)
             (vector-set! v i (vector-ref v j))
             (vector-set! v j elt-i))
           (lp (- i 1)))))
  v)


;;; This is the core of the algorithm.

(define (dig-maze walls ncells)
  (vector-until-rev
      (lambda (wall);; For each wall,
        (let* ((c1   (wall:owner wall));; find the cells on
               (set1 (cell:reachable c1))

               (c2   (wall:neighbor wall));; each side of the wall
               (set2 (cell:reachable c2)))

;;; If there is no path from c1 to c2, knock down the
;;; wall and union the two sets of reachable cells.
;;; If the new set of reachable cells is the whole set
;;; of cells, quit.
          (and (not (set-equal? set1 set2))
              (let ((walls (cell:walls c1))
                    (wall-mask (bitwise-not (wall:bit wall))))
                (union! set1 set2)
                (set-cell:walls c1 (bitwise-and walls wall-mask))
                (= (set-size set1) ncells)))))
      walls))


;;; Some simple DFS routines useful for determining path length
;;; through the maze.

;;; Build a DFS tree from ROOT.
;;; (DO-CHILDREN proc maze node) applies PROC to each of NODE's children.
;;; We assume there are no loops in the maze; if this is incorrect, the
;;; algorithm will diverge.

(define (dfs-maze maze root do-children)
  (let search ((node root) (parent (absent)))
    (set-cell:parent node parent)
    (do-children (lambda (child)
                   (if (not (same-cell-parent? child parent))
                       (search child (present node))))
                 maze node)))

;;; Move the root to NEW-ROOT.

(define (reroot-maze new-root)
  (let lp ((node new-root) (new-parent (absent)))
    (let ((old-parent (cell:parent node)))
      (set-cell:parent node new-parent)
      (if (present? old-parent) (lp (optional-value old-parent) (present node))))))

;;; How far from CELL to the root?

(define (path-length cell)
  (maze-do ((len 0 (+ len 1))
       (node (cell:parent cell) (cell:parent (optional-value node))))
      ((not (present? node)) len)))

;;; Mark the nodes from NODE back to root. Used to mark the winning path.

(define (mark-path node)
  (let lp ((node node))
    (set-cell:mark node #t)
    (maze-cond ((cell:parent node) => lp))))

;;------------------------------------------------------------------------------
;; Was file "harr.scm".

;;; Hex arrays
;;; Copyright (c) 1995 by Olin Shivers.

;;; External dependencies:
;;; - define-record

;;;        ___       ___       ___
;;;       /   \     /   \     /   \
;;;   ___/  A  \___/  A  \___/  A  \___
;;;  /   \     /   \     /   \     /   \
;;; /  A  \___/  A  \___/  A  \___/  A  \
;;; \     /   \     /   \     /   \     /
;;;  \___/     \___/     \___/     \___/
;;;  /   \     /   \     /   \     /   \
;;; /     \___/     \___/     \___/     \
;;; \     /   \     /   \     /   \     /
;;;  \___/     \___/     \___/     \___/
;;;  /   \     /   \     /   \     /   \
;;; /     \___/     \___/     \___/     \
;;; \     /   \     /   \     /   \     /
;;;  \___/     \___/     \___/     \___/

;;; Hex arrays are indexed by the (x,y) coord of the center of the hexagonal
;;; element. Hexes are three wide and two high; e.g., to get from the center
;;; of an elt to its {NW, N, NE} neighbors, add {(-3,1), (0,2), (3,1)}
;;; respectively.
;;;
;;; Hex arrays are represented with a matrix, essentially made by shoving the
;;; odd columns down a half-cell so things line up. The mapping is as follows:
;;;     Center coord      row/column
;;;     ------------      ----------
;;;     (x,  y)        -> (y/2, x/3)
;;;     (3c, 2r + c&1) <- (r,   c)


;; (define-record harr
;;   nrows
;;   ncols
;;   elts)

(define (make-harr nrows ncols elts)
  (harr-record (ref nrows) (ref ncols) (ref elts)))

(define (harr:nrows o)       (ref-get (harr-rows-field o)))
(define (set-harr:nrows o v) (ref-set! (harr-rows-field o) v))
(define (harr:ncols o)       (ref-get (harr-columns-field o)))
(define (set-harr:ncols o v) (ref-set! (harr-columns-field o) v))
(define (harr:elts o)        (ref-get (harr-elements-field o)))
(define (set-harr:elts o v)  (ref-set! (harr-elements-field o) v))

(define (harr r c)
  (make-harr r c (make-vector (* r c) (uninitialized-cell))))



(define (href ha x y)
  (let ((r (div y 2))
        (c (div x 3)))
    (vector-ref (harr:elts ha)
                (+ (* (harr:ncols ha) r) c))))

(define (hset! ha x y val)
  (let ((r (div y 2))
        (c (div x 3)))
    (vector-set! (harr:elts ha)
                 (+ (* (harr:ncols ha) r) c)
                 val)))

(define (href/rc ha r c)
  (vector-ref (harr:elts ha)
              (+ (* (harr:ncols ha) r) c)))

;;; Create a nrows x ncols hex array. The elt centered on coord (x, y)
;;; is the value returned by (PROC x y).

(define (harr-tabulate nrows ncols proc)
  (let ((v (make-vector (* nrows ncols) (uninitialized-cell))))

    (maze-do ((r (- nrows 1) (- r 1)))
        ((< r 0))
      (maze-do ((c 0 (+ c 1))
           (i (* r ncols) (+ i 1)))
          ((= c ncols))
        (vector-set! v i (proc (* 3 c) (+ (* 2 r) (bitwise-and c 1))))))

    (make-harr nrows ncols v)))


(define (harr-for-each proc harr)
  (vector-for-each-rev proc (harr:elts harr)))

;;------------------------------------------------------------------------------
;; Was file "hex.scm".

;;; Hexagonal hackery for maze generation.
;;; Copyright (c) 1995 by Olin Shivers.

;;; External dependencies:
;;; - cell and wall records
;;; - Functional Postscript for HEXES->PATH
;;; - logical functions for bit hacking
;;; - hex array code.

;;; To have the maze span (0,0) to (1,1):
;;; (scale (/ (+ 1 (* 3 ncols))) (/ (+ 1 (* 2 nrows)))
;;;        (translate (point 2 1) maze))

;;; Every elt of the hex array manages his SW, S, and SE wall.
;;; Terminology: - An even column is one whose column index is even. That
;;;                means the first, third, ... columns (indices 0, 2, ...).
;;;              - An odd column is one whose column index is odd. That
;;;                means the second, fourth... columns (indices 1, 3, ...).
;;;              The even/odd flip-flop is confusing; be careful to keep it
;;;              straight. The *even* columns are the low ones. The *odd*
;;;              columns are the high ones.
;;;    _   _
;;;  _/ \_/ \
;;; / \_/ \_/
;;; \_/ \_/ \
;;; / \_/ \_/
;;; \_/ \_/ \
;;; / \_/ \_/
;;; \_/ \_/ \
;;; / \_/ \_/
;;; \_/ \_/
;;;  0 1 2 3

(define south-west 1)
(define south      2)
(define south-east 4)

(define (gen-maze-array r c)
  (harr-tabulate r c (lambda (x y) (make-cell (base-set 1) (coordinate x y)))))

;;; This could be made more efficient.
(define (make-wall-vec harr)
  (let* ((nrows (harr:nrows harr))
         (ncols (harr:ncols harr))
         (xmax (* 3 (- ncols 1)))

;;; Accumulate walls.
         (walls (ref (ann '() (List Wall))))
         (add-wall (lambda (o n b);; owner neighbor bit
                     (ref-set! walls (cons (make-wall o n b) (ref-get walls))))))

;;; Do everything but the bottom row.
    (maze-do ((x (* (- ncols 1) 3) (- x 3)))
        ((< x 0))
      (maze-do ((y (+ (* (- nrows 1) 2) (bitwise-and x 1))
              (- y 2)))
          ((<= y 1));; Don't do bottom row.
        (let ((hex (href harr x y)))
          (if (not (maze-zero? x))
              (add-wall hex (href harr (- x 3) (- y 1)) south-west))
          (add-wall hex (href harr x (- y 2)) south)
          (if (< x xmax)
              (add-wall hex (href harr (+ x 3) (- y 1)) south-east)))))

;;; Do the SE and SW walls of the odd columns on the bottom row.
;;; If the rightmost bottom hex lies in an odd column, however,
;;; don't add it's SE wall -- it's a corner hex, and has no SE neighbor.
    (if (> ncols 1)
        (let ((rmoc-x (+ 3 (* 6 (div (- ncols 2) 2)))))
;;; Do rightmost odd col.
          (let ((rmoc-hex (href harr rmoc-x 1)))
            (if (< rmoc-x xmax);; Not  a corner -- do E wall.
                (add-wall rmoc-hex (href harr xmax 0) south-east))
            (add-wall rmoc-hex (href harr (- rmoc-x 3) 0) south-west))

          (maze-do ((x (- rmoc-x 6);; Do the rest of the bottom row's odd cols.
                  (- x 6)))
              ((< x 3));; 3 is X coord of leftmost odd column.
            (add-wall (href harr x 1) (href harr (- x 3) 0) south-west)
            (add-wall (href harr x 1) (href harr (+ x 3) 0) south-east))))

    (list->vector (ref-get walls))))


;;; Find the cell ctop from the top row, and the cell cbot from the bottom
;;; row such that cbot is furthest from ctop.
;;; Return [ctop-x, ctop-y, cbot-x, cbot-y].

(define (pick-entrances harr)
  (dfs-maze harr (href/rc harr 0 0) for-each-hex-child)
  (let ((nrows (harr:nrows harr))
        (ncols (harr:ncols harr)))
    (let tp-lp ((max-len -1)
                (entrance (absent))
                (exit (absent))
                (tcol (- ncols 1)))
      (if (< tcol 0) (entrances entrance exit)
          (let ((top-cell (href/rc harr (- nrows 1) tcol)))
            (reroot-maze top-cell)
            (let ((result
                   (let bt-lp ((max-len max-len)
                               (entrance entrance)
                               (exit exit)
                               (bcol (- ncols 1)))
                     ;;                     (format #t "~a ~a ~a ~a~%" max-len entrance exit bcol)
                     (if (< bcol 0) (longest-path max-len entrance exit)
                         (let ((this-len (path-length (href/rc harr 0 bcol))))
                           (if (> this-len max-len)
                               (bt-lp this-len (present tcol) (present bcol) (- bcol 1))
                               (bt-lp max-len  entrance exit (- bcol 1))))))))
              (let ((max-len (longest-length result))
                    (entrance (longest-top result))
                    (exit (longest-bottom result)))
                (tp-lp max-len entrance exit (- tcol 1)))))))))



;;; Apply PROC to each node reachable from CELL.
(define (for-each-hex-child proc harr cell)
  (let* ((walls (cell:walls cell))
         (id (cell:id cell))
         (x (coordinate-x id))
         (y (coordinate-y id))
         (nr (harr:nrows harr))
         (nc (harr:ncols harr))
         (maxy (* 2 (- nr 1)))
         (maxx (* 3 (- nc 1))))
    (if (not (bit-test walls south-west)) (proc (href harr (- x 3) (- y 1))))
    (if (not (bit-test walls south))      (proc (href harr x       (- y 2))))
    (if (not (bit-test walls south-east)) (proc (href harr (+ x 3) (- y 1))))

;;; NW neighbor, if there is one (we may be in col 1, or top row/odd col)
    (if (and (> x 0);; Not in first column.
             (or (<= y maxy);; Not on top row or
                 (maze-zero? (mod x 6))));; not in an odd column.
        (let ((nw (href harr (- x 3) (+ y 1))))
          (if (not (bit-test (cell:walls nw) south-east)) (proc nw))))

;;; N neighbor, if there is one (we may be on top row).
    (if (< y maxy);; Not on top row
        (let ((n (href harr x (+ y 2))))
          (if (not (bit-test (cell:walls n) south)) (proc n))))

;;; NE neighbor, if there is one (we may be in last col, or top row/odd col)
    (if (and (< x maxx);; Not in last column.
             (or (<= y maxy);; Not on top row or
                 (maze-zero? (mod x 6))));; not in an odd column.
        (let ((ne (href harr (+ x 3) (+ y 1))))
          (if (not (bit-test (cell:walls ne) south-west)) (proc ne))))))



;;; The top-level
(define (make-maze nrows ncols)
  (let* ((cells (gen-maze-array nrows ncols))
         (walls (permute-vec! (make-wall-vec cells) (random-state 20))))
    (dig-maze walls (* nrows ncols))
    (let ((result (pick-entrances cells)))
      (let ((entrance (optional-value (entrance-top result)))
            (exit (optional-value (entrance-bottom result))))
        (let* ((exit-cell (href/rc cells 0 exit))
               (walls (cell:walls exit-cell)))
          (reroot-maze (href/rc cells (- nrows 1) entrance))
          (mark-path exit-cell)
          (set-cell:walls exit-cell (bitwise-and walls (bitwise-not south)))
          (maze-result cells entrance exit))))))


(define (pmaze nrows ncols)
  (let ((result (make-maze nrows ncols)))
    (let ((cells (maze-cells result))
          (entrance (maze-entrance result))
          (exit (maze-exit result)))
      (print-hexmaze cells entrance))))

;;------------------------------------------------------------------------------
;; Was file "hexprint.scm".

;;; Print out a hex array with characters.
;;; Copyright (c) 1995 by Olin Shivers.

;;; External dependencies:
;;; - hex array code
;;; - hex cell code

;;;    _   _
;;;  _/ \_/ \
;;; / \_/ \_/
;;; \_/ \_/ \
;;; / \_/ \_/
;;; \_/ \_/ \
;;; / \_/ \_/
;;; \_/ \_/ \
;;; / \_/ \_/
;;; \_/ \_/

;;; Top part of top row looks like this:
;;;    _   _  _   _
;;;  _/ \_/ \/ \_/ \
;;; /

(define output (ref (ann '() (List Char))));; the list of all characters written out, in reverse order.

(define (write-ch c)
  (ref-set! output (cons c (ref-get output))))

(define (print-hexmaze harr entrance)
  (let* ((nrows  (harr:nrows harr))
         (ncols  (harr:ncols harr))
         (ncols2 (* 2 (div ncols 2))))

;;; Print out the flat tops for the top row's odd cols.
    (maze-do ((c 1 (+ c 2)))
        ((>= c ncols))
      ;;     (display "   ")
      (write-ch #\space)
      (write-ch #\space)
      (write-ch #\space)
      (write-ch (if (= c entrance) #\space #\_)))
    ;;   (newline)
    (write-ch #\newline)

;;; Print out the slanted tops for the top row's odd cols
;;; and the flat tops for the top row's even cols.
    (write-ch #\space)
    (maze-do ((c 0 (+ c 2)))
        ((>= c ncols2))
      ;;     (format #t "~a/~a\\"
      ;;             (if (= c entrance) #\space #\_)
      ;;             (dot/space harr (- nrows 1) (+ c 1)))
      (write-ch (if (= c entrance) #\space #\_))
      (write-ch #\/)
      (write-ch (dot/space harr (- nrows 1) (+ c 1)))
      (write-ch #\\))
    (if (maze-odd? ncols)
        (write-ch (if (= entrance (- ncols 1)) #\space #\_)))
    ;;   (newline)
    (write-ch #\newline)

    (maze-do ((r (- nrows 1) (- r 1)))
        ((< r 0))

;;; Do the bottoms for row r's odd cols.
      (write-ch #\/)
      (maze-do ((c 1 (+ c 2)))
          ((>= c ncols2))
;;; The dot/space for the even col just behind c.
        (write-ch (dot/space harr r (- c 1)))
        (display-hexbottom (cell:walls (href/rc harr r c))))

      (maze-cond ((maze-odd? ncols)
             (write-ch (dot/space harr r (- ncols 1)))
             (write-ch #\\)))
      ;;     (newline)
      (write-ch #\newline)

;;; Do the bottoms for row r's even cols.
      (maze-do ((c 0 (+ c 2)))
          ((>= c ncols2))
        (display-hexbottom (cell:walls (href/rc harr r c)))
;;; The dot/space is for the odd col just after c, on row below.
        (write-ch (dot/space harr (- r 1) (+ c 1))))

      (maze-cond ((maze-odd? ncols)
             (display-hexbottom (cell:walls (href/rc harr r (- ncols 1)))))
            ((not (maze-zero? r)) (write-ch #\\)))
      ;;     (newline)
      (write-ch #\newline))))

(define (bit-test j bit)
  (not (maze-zero? (bitwise-and j bit))))

;;; Return a . if harr[r,c] is marked, otherwise a space.
;;; We use the dot to mark the solution path.
(define (dot/space harr r c)
  (if (and (>= r 0) (cell:mark (href/rc harr r c))) #\. #\space))

;;; Print a \_/ hex bottom.
(define (display-hexbottom hexwalls)
  (write-ch (if (bit-test hexwalls south-west) #\\ #\space))
  (write-ch (if (bit-test hexwalls south     ) #\_ #\space))
  (write-ch (if (bit-test hexwalls south-east) #\/ #\space)))

;;;    _   _
;;;  _/ \_/ \
;;; / \_/ \_/
;;; \_/ \_/ \_/
;;; / \_/ \_/
;;; \_/ \_/ \
;;; / \_/ \_/
;;; \_/ \_/ \
;;; / \_/ \_/
;;; \_/ \_/ \_/

;;------------------------------------------------------------------------------

(define (run nrows ncols)
  (ref-set! output '())
  (pmaze nrows ncols)
  (maze-reverse (ref-get output)))

(define (run-benchmark)
  (let* ((count (read))
         (input1 (read))
         (input2 (read))
         (output (chez-output (read)))
         (s3 (number->string count))
         (s2 (number->string input2))
         (s1 (number->string input1))
         (name "maze"))
    (run-r7rs-benchmark
     (string-append name ":" s1 ":" s2 ":" s3)
     count
     (lambda () (character-output (run (hide count input1) (hide count input2))))
     (lambda (result) (same-output? result output)))))

(define (this-scheme-implementation-name) "chez")

;;; The following code is appended to all benchmarks.

;;; Given an integer and an object, returns the object
;;; without making it too easy for compilers to tell
;;; the object will be returned.

(define (hide r x)
  (call-with-values
   (lambda ()
     (values (vector values (lambda (x) x))
             (if (< r 100) 0 1)))
   (lambda (v i)
     ((vector-ref v i) x))))

;;; Given the name of a benchmark,
;;; the number of times it should be executed,
;;; a thunk that runs the benchmark once,
;;; and a unary predicate that is true of the
;;; correct results the thunk may return,
;;; runs the benchmark for the number of specified iterations.

(define (run-r7rs-benchmark name count thunk ok?)

  ;; Rounds to thousandths.
  (define (rounded x)
    (/ (round (* 1000 x)) 1000))

  (display "Running ")
  (display name)
  (newline)
  (flush-output-port (current-output-port))
  (let* ((j/s (jiffies-per-second))
         (t0 (current-second))
         (j0 (current-jiffy)))
    (let loop ((i 0)
               (result (initial-output)))
      (cond ((< i count)
             (loop (+ i 1) (thunk)))
            ((ok? result)
             (let* ((t1 (current-second))
                    (j1 (current-jiffy))
                    (jifs (- j1 j0))
                    (secs (inexact (/ jifs j/s)))
                    (secs2 (rounded (- t1 t0))))
               (display "Elapsed time: ")
               (write secs)
               (display " seconds (")
               (write secs2)
               (display ") for ")
               (display name)
               (newline)
               (display "+!CSVLINE!+")
               (display (this-scheme-implementation-name))
               (display ",")
               (display name)
               (display ",")
               (display secs)
               (newline)
               (flush-output-port (current-output-port)))
             0)
            (else
             (display "ERROR: returned incorrect result: ")
             (write (original-output result))
             (newline)
             (display "+!CSVLINE!+")
             (display (this-scheme-implementation-name))
             (display ",")
             (display name)
             (display ",")
             (display "INCORRECT")
             (newline)
             (flush-output-port (current-output-port))
             0)))))

(run-benchmark)
