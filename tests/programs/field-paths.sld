(import
 (snail core base)
 (snail core io))

;; Nominal projections select stored slots. The book's types chapter
;; includes the text between ANCHOR and ANCHOR_END.
;; ANCHOR: paths
(record Point
  ((x I64)
   (y I64)))

(record Segment
  ((from Point)
   (to Point)
   (label String)))

(record Tag
  ((label String)
   (weight I64)))

(define (describe (segment Segment)) (→ String)
  (string-append (● segment label)
                 ": "
                 (show (● segment from x))
                 " to "
                 (show (● segment to x))))

;; A generic nominal record still identifies the slot being read.
(define (labelled (record (Pair T String))) (→ String) (∀ (T))
  (string-append "[" (● record second) "]"))

;; Computation uses an ordinary function; projection always means storage.
(record Circle
  ((radius I64)))

(define (diameter (circle Circle)) (→ I64)
  (* 2 (● circle radius)))

(define (main) (→ Unit) (! output-port)

  ;; ANCHOR_END: paths

  (write-line (describe (new Segment
                          (from (new Point (x 1) (y 2)))
                          (to (new Point (x 3) (y 4)))
                          (label "diagonal"))))
  (write-line (● (new Tag (label "heavy") (weight 9)) label))
  (write-line (show (● (new Tag (label "heavy") (weight 9)) weight)))
  (write-line (labelled (new Pair (first 1) (second "t"))))
  (write-line (labelled (new Pair (first #t) (second "s"))))
  ;; A lambda can use a projection as a higher-order selector.
  (write-line
   (string-join (map show
                     (map (lambda (record) (● record x))
                          (list (new Point (x 5) (y 0)) (new Point (x 6) (y 0)))))
                " "))
  (write-line
   (string-join (map (lambda (record) (● record label))
                     (list (new Tag (label "a") (weight 1)) (new Tag (label "b") (weight 2))))
                " "))
  (write-line (show (diameter (new Circle (radius 21)))))
  ;; Instantiating a nominal record substitutes its field types.
  (write-line (show (● (new Pair (first 7) (second "seven")) first)))
  (write-line (● (new Pair (first 7) (second "seven")) second))
  (unit))
