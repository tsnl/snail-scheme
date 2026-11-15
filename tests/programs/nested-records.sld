(import
 (snail core base)
 (snail core io))

;; Every nested record is a separate heap object. Fields hold references,
;; so constructing a Segment preserves the identity of its Point arguments.
;; ANCHOR: segment
(record Point
  ((x I64)
   (y I64)))

(record Segment
  ((from Point)
   (to Point)
   (label String)))

;; ANCHOR_END: segment

(define (show-point (point Point)) (→ String)
  (match point
    ((Point x y) (string-append "(" (show x) ", " (show y) ")"))))

(define (show-segment (segment Segment)) (→ String)
  (string-append (● segment label)
                 ": "
                 (show-point (● segment from))
                 " to "
                 (show-point (● segment to))))

;; A pure replacement makes a new record with one field replaced. The
;; replacement expression can inspect the record's fields.
(record Job
  ((at Point)
   (work (Fn → Unit ! output-port))))

(define (flip (job Job)) (→ Job)
  (Job-at-set job (new Point (x (● (● job at) y)) (y (● (● job at) x)))))

(define (nearest (points (List Point))) (→ Point)
  (fold-left (lambda (best point) (if (< (● point x) (● best x)) point best))
             (new Point (x 100) (y 100))
             points))

;; An enum case holds object references after its tag.
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

;; Each nested Point can be mutated or replaced independently.
(record Cursor
  ((home Point)
   (clicks I64)
   (last Point)))

;; A call that may yield leaves an inactive result, here null for a
;; Segment, before the frames resume.
(effect Ask
  ((ctl ask (Fn → I64))))

(define (build) (→ Segment) (! Ask)
  (new Segment (from (new Point (x (ask)) (y 0))) (to (new Point (x 0) (y (ask)))) (label "asked")))

(define (main) (→ Unit) (! mut output-port)

  ;; Nested construction, a chain of accessors, and a nested pattern.
  (let ((segment (new Segment
                   (from (new Point (x 1) (y 2)))
                   (to (new Point (x 3) (y 4)))
                   (label "diagonal"))))
    (write-line (show-segment segment))
    (write-line (show (● (● segment to) y)))
    (match segment
      ((Segment (Point x _) to label)
       (write-line
        (string-append label " starts at x " (show x) " and ends at " (show-point to))))))
  ;; A pure replacement creates a new outer record and shares other fields.
  (let* ((segment
          (new Segment (from (new Point (x 0) (y 0))) (to (new Point (x 1) (y 1))) (label "unit")))
         (moved (Segment-to-set segment (new Point (x 5) (y 5)))))
    (write-line (show-segment segment))
    (write-line (show-segment moved)))
  (match (flip
          (new Job (at (new Point (x 1) (y 2))) (work (lambda () (write-line "worked")))))
    ((Job at work)
     (write-line (show-point at))
     (work)))
  ;; A generic record also stores its object argument by reference.
  (let ((pair (new Pair (first (new Point (x 7) (y 8))) (second "seven-eight"))))
    (write-line (string-append (● pair second) " " (show-point (● pair first)))))
  (write-line (show-point (nearest (list (new Point (x 3) (y 1))
                                         (new Point (x 2) (y 9))
                                         (new Point (x 5) (y 5))))))
  (for-each (lambda (shape) (write-line (describe shape)))
            (list (Dot (new Point (x 4) (y 4)))
                  (Line (new Segment
                          (from (new Point (x 0) (y 1)))
                          (to (new Point (x 2) (y 3)))
                          (label "l")))
                  (Empty)))
  (match (Dot (new Point (x 6) (y 0)))
    ((Dot at) (write-line (show (● at x))))
    (_ (panic "expected dot")))
  (let ((cursor
         (new Cursor (home (new Point (x 0) (y 0))) (clicks 0) (last (new Point (x 1) (y 1))))))
    (set! (● cursor clicks) (+ (● cursor clicks) 1))
    (set! (● cursor last) (new Point (x 2) (y 2)))
    (write-line (string-append (show (● cursor clicks))
                               " "
                               (show-point (● cursor home))
                               " "
                               (show-point (● cursor last))))
    (write-line (show-point (● cursor last)))
    (set! (● cursor last) (new Point (x 3) (y 3)))
    (write-line (show-point (● cursor last))))
  ;; Accessors are functions too, and an Any holds a Point as itself.
  (write-line
   (string-join (map show
                     (map (lambda (record) (● record x))
                          (list (new Point (x 1) (y 0)) (new Point (x 2) (y 0)))))
                " "))
  (write-line (show-point (match (downcast Point (Any (new Point (x 9) (y 9))))
                            ((Some value) value)
                            ((None) (panic "point round trip failed")))))
  (write-line (show-segment (handle Ask
                                ((ask (lambda (resume) (resume 1))))
                              (build))))
  (unit))
