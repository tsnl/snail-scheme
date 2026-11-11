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

(define (show-point (point Point)) (→ String)
  (match point
    ((Point x y) (string-append "(" (show x) ", " (show y) ")"))))

(define (show-segment (segment Segment)) (→ String)
  (string-append (::label segment)
                 ": "
                 (show-point (::from segment))
                 " to "
                 (show-point (::to segment))))

;; Nested construction, a chain of accessors, and a nested pattern.
(let ((segment (Segment (Point 1 2) (Point 3 4) "diagonal")))
  (write-line (show-segment segment))
  (write-line (show (::y (::to segment))))
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
   (work (dyn (FnOnce → Unit ! console)))))

(define (flip (job Job)) (→ Job)
  (Job-at-set job (Point (::y (::at job)) (::x (::at job)))))

(match (flip (Job (Point 1 2) (once (lambda () (write-line "worked")))))
  ((Job at work)
   (write-line (show-point at))
   (call-once work)))

;; A generic struct lays an inline argument out where it is instantiated.
(let ((pair (Pair (Point 7 8) "seven-eight")))
  (write-line (string-append (::second pair) " " (show-point (::first pair)))))

(define (nearest (points (List Point))) (→ Point)
  (fold-left (lambda (best point) (if (< (::x point) (::x best)) point best))
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

(define (describe (shape Shape)) (→ String)
  (match shape
    ((Dot (Point x y)) (string-append "dot at " (show x) "," (show y)))
    ((Line segment) (string-append "line " (show-segment segment)))
    ((Empty) "nothing")))

(for-each (lambda (shape) (write-line (describe shape)))
          (list (Dot (Point 4 4)) (Line (Segment (Point 0 1) (Point 2 3) "l")) (Empty)))
(write-line (show (::x (Dot-at (Dot (Point 6 0))))))

;; A struct a program changes lives in a cell, whose slots are the
;; struct's: a cell of a Cursor is one object of five slots, and a field
;; of a Point inside is one of them.
(struct Cursor
  ((home Point)
   (clicks I64)
   (last Point)))

(let ((cursor (ref (Cursor (Point 0 0) 0 (Point 1 1)))))
  (set! (::clicks (ref-get cursor)) (+ (::clicks (ref-get cursor)) 1))
  (set! (::last (ref-get cursor)) (Point 2 2))
  (write-line (string-append (show (::clicks (ref-get cursor)))
                             " "
                             (show-point (::home (ref-get cursor)))
                             " "
                             (show-point (::last (ref-get cursor)))))
  (write-line (show-point (replace! (::last (ref-get cursor)) (Point 3 3))))
  (write-line (show-point (::last (ref-get cursor)))))

;; Accessors are functions too, and an Any holds a Point as itself.
(write-line (string-join (map show (map ::x (list (Point 1 0) (Point 2 0)))) " "))
(write-line (show-point (match (try-convert (type-convert (Point 9 9) Any) Point)
                          ((Ok value) value)
                          ((Err _) (panic "point round trip failed")))))

;; A call that may yield leaves with a placeholder of its type, here a
;; Segment, before the frames resume.
(effect Ask
  ((ctl ask (dyn (Fn → I64)))))

(define (build) (→ Segment) (! Ask)
  (Segment (Point (ask) 0) (Point 0 (ask)) "asked"))

(write-line (show-segment (handle Ask
                              ((ask (lambda (resume) (resume 1))))
                            (build))))
