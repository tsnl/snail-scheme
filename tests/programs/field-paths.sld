(import
 (snail core base)
 (snail core io))

;; `::label` reads the field `label` of whatever struct it is given. Each
;; label is a typeclass over the record and the field's type, with an
;; instance per struct declaring the field, and the record's type decides
;; the field's; `::a::b` chains two reads. The book's types chapter includes
;; the text between ANCHOR and ANCHOR_END.
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

(: describe (-> Segment String))
(define (describe segment)
  (string-append (::label segment)
                 ": "
                 (show (::from::x segment))
                 " to "
                 (show (::to::x segment))))
;; ANCHOR_END: paths

(write-line (describe (Segment (Point 1 2) (Point 3 4) "diagonal")))
(write-line (::label (Tag "heavy" 9)))
(write-line (show (::weight (Tag "heavy" 9))))

;; A generic function reads a field of any record that has it.
(: labelled (All (R) (requires (::label R String)) (-> R String)))
(define (labelled record)
  (string-append "[" (::label record) "]"))

(write-line (labelled (Tag "t" 1)))
(write-line (labelled (Segment (Point 0 0) (Point 1 1) "s")))

;; A path is a function.
(write-line (string-join (map show (map ::x (list (Point 5 0) (Point 6 0)))) " "))
(write-line (string-join (map ::label (list (Tag "a" 1) (Tag "b" 2))) " "))

;; A type without the field may declare the instance itself: a computed
;; field.
(struct Circle
  ((radius I64)))

(instance (::x Circle I64)
  (define (::x circle)
    (* 2 (Circle-radius circle))))

(write-line (show (::x (Circle 21))))

;; A generic struct's instance is generic too.
(write-line (show (::first (Pair 7 "seven"))))
(write-line (::second (Pair 7 "seven")))
