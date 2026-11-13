(import
 (snail core base)
 (snail core io))

;; Nominal projections select stored slots. The book's types chapter
;; includes the text between ANCHOR and ANCHOR_END.
;; ANCHOR: paths
(struct Point
  ((x I64)
   (y I64)))

(struct Segment
  ((from Point)
   (to Point)
   (label String)))

(struct Tag
  ((label String)
   (weight I64)))

(define (describe (segment Segment)) (→ String)
  (string-append (● segment label)
                 ": "
                 (show (● segment from x))
                 " to "
                 (show (● segment to x))))

;; A generic nominal record still identifies the slot being read.
(define (labelled (record (Pair T String))) (→ String) (∀ (T)) (⊨ (Copy T) (Drop (!) T))
  (string-append "[" (● record second) "]"))

;; Computation uses an ordinary function; projection always means storage.
(struct Circle
  ((radius I64)))

(define (diameter (circle Circle)) (→ I64)
  (* 2 (● circle radius)))

(define main
  (lambda ()
    ;; ANCHOR_END: paths

    (write-line (describe (Segment (Point 1 2) (Point 3 4) "diagonal")))
    (write-line (● (Tag "heavy" 9) label))
    (write-line (show (● (Tag "heavy" 9) weight)))
    (write-line (labelled (Pair 1 "t")))
    (write-line (labelled (Pair #t "s")))
    ;; A lambda can use a projection as a higher-order selector.
    (write-line
     (string-join (map show (map (lambda (record) (● record x)) (list (Point 5 0) (Point 6 0))))
                  " "))
    (write-line
     (string-join (map (lambda (record) (● record label)) (list (Tag "a" 1) (Tag "b" 2))) " "))
    (write-line (show (diameter (Circle 21))))
    ;; Instantiating a nominal record substitutes its field types.
    (write-line (show (● (Pair 7 "seven") first)))
    (write-line (● (Pair 7 "seven") second))
    (unit)))
