(import
 (snail core base)
 (snail core io))

;; A struct with no mutable field has no identity, so an immutable field
;; holding one is laid out inline: a Segment is one GC struct of five
;; slots, with no Point in it. The program cannot tell, except that nothing
;; here allocates a Point until one is named on its own. The book's
;; ownership chapter includes the text between ANCHOR and ANCHOR_END.
;; ANCHOR: segment
(struct Point
  ((x I64)
   (y I64)))

(struct Segment
  ((from Point)
   (to Point)
   (label String)))
;; ANCHOR_END: segment

(: show-point (-> Point String))
(define (show-point point)
  (match point
    ((Point x y) (string-append "(" (show x) ", " (show y) ")"))))

(: show-segment (-> Segment String))
(define (show-segment segment)
  (string-append (Segment-label segment)
                 ": "
                 (show-point (Segment-from segment))
                 " to "
                 (show-point (Segment-to segment))))

;; Nested construction, a chain of accessors, and a nested pattern.
(let ((segment (Segment (Point 1 2) (Point 3 4) "diagonal")))
  (write-line (show-segment segment))
  (write-line (show (Point-y (Segment-to segment))))
  (match segment
    ((Segment (Point x _) to label)
     (write-line (string-append label " starts at x " (show x) " and ends at " (show-point to))))))

;; A replacement of an inline field copies an unrestricted record, so the
;; original is unchanged.
(let* ((segment (Segment (Point 0 0) (Point 1 1) "unit"))
       (moved (Segment-to-set segment (Point 5 5))))
  (write-line (show-segment segment))
  (write-line (show-segment moved)))

;; A linear record is replaced in place, slot by slot. The replacement may
;; read the record it replaces, so its slots are evaluated before any is
;; written.
(struct Job
  ((at Point)
   (work (FnOnce Unit ! console))))

(: flip (-> Job Job))
(define (flip job)
  (Job-at-set job (Point (Point-y (Job-at job)) (Point-x (Job-at job)))))

(match (flip (Job (Point 1 2) (once (lambda () (write-line "worked")))))
  ((Job at work)
   (write-line (show-point at))
   (call-once work)))

;; A generic struct lays an inline argument out where it is instantiated.
(let ((pair (Pair (Point 7 8) "seven-eight")))
  (write-line (string-append (Pair-second pair) " " (show-point (Pair-first pair)))))

(: nearest (-> (List Point) Point))
(define (nearest points)
  (fold-left (lambda (best point) (if (< (Point-x point) (Point-x best)) point best))
             (Point 100 100)
             points))

(write-line (show-point (nearest (list (Point 3 1) (Point 2 9) (Point 5 5)))))

;; An enum case holds inline fields after its tag.
(enum Shape
  (Dot
   ((at Point)))
  (Line
   ((segment Segment)))
  (Empty))

(: describe (-> Shape String))
(define (describe shape)
  (match shape
    ((Dot (Point x y)) (string-append "dot at " (show x) "," (show y)))
    ((Line segment) (string-append "line " (show-segment segment)))
    ((Empty) "nothing")))

(for-each (lambda (shape) (write-line (describe shape)))
          (list (Dot (Point 4 4)) (Line (Segment (Point 0 1) (Point 2 3) "l")) (Empty)))
(write-line (show (Point-x (Dot-at (Dot (Point 6 0))))))

;; A struct with a mutable field has identity and stays a reference, while
;; its immutable Point is inline; a mutable field of a Point holds a
;; reference.
(struct Cursor
  ((home Point)
   (clicks mut I64)
   (last mut Point)))

(let ((cursor (Cursor (Point 0 0) 0 (Point 1 1))))
  (Cursor-clicks-set! cursor (+ (Cursor-clicks cursor) 1))
  (Cursor-last-set! cursor (Point 2 2))
  (write-line (string-append (show (Cursor-clicks cursor))
                             " "
                             (show-point (Cursor-home cursor))
                             " "
                             (show-point (Cursor-last cursor))))
  (write-line (show-point (Cursor-last-replace! cursor (Point 3 3))))
  (write-line (show-point (Cursor-last cursor))))

;; Accessors are functions too, and an Any holds a Point as itself.
(write-line (string-join (map show (map Point-x (list (Point 1 0) (Point 2 0)))) " "))
(write-line (show-point (type-convert (type-convert (Point 9 9) Any) Point)))

;; A call that may yield leaves with a placeholder of its type, here a
;; Segment, before the frames resume.
(effect Ask
  ((ctl ask (-> I64))))

(: build (-> Segment ! Ask))
(define (build)
  (Segment (Point (ask) 0) (Point 0 (ask)) "asked"))

(write-line (show-segment (handle Ask
                              ((ask (lambda (resume) (resume 1))))
                            (build))))
