(import
 (snail core base)
 (snail core io))

;; Every nested struct is a separate heap object. Fields hold references,
;; so constructing a Segment preserves the identity of its Point arguments.
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
  (string-append (● segment label)
                 ": "
                 (show-point (● segment from))
                 " to "
                 (show-point (● segment to))))

;; A pure replacement transfers a linear record into its result. The
;; replacement expression can inspect fields before that transfer.
(struct Job
  ((at Point)
   (work (FnOnce → Unit ! output-port))))

(define (flip (job Job)) (→ Job)
  (Job-at-set job (Point (● (● job at) y) (● (● job at) x))))

(define (nearest (points (List Point))) (→ Point)
  (fold-left (lambda (best point) (if (< (● point x) (● best x)) point best))
             (Point 100 100)
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
(struct Cursor
  ((home Point)
   (clicks I64)
   (last Point)))

;; A call that may yield leaves an inactive result, here null for a
;; Segment, before the frames resume.
(effect Ask
  ((ctl ask (Fn → I64))))

(define (build) (→ Segment) (! Ask)
  (Segment (Point (ask) 0) (Point 0 (ask)) "asked"))

(define main
  (lambda ()
    ;; Nested construction, a chain of accessors, and a nested pattern.
    (let ((segment (Segment (Point 1 2) (Point 3 4) "diagonal")))
      (write-line (show-segment segment))
      (write-line (show (● (● segment to) y)))
      (match segment
        ((Segment (Point x _) to label)
         (write-line
          (string-append label " starts at x " (show x) " and ends at " (show-point to))))))
    ;; A pure replacement creates a new outer record and shares other fields.
    (let* ((segment (Segment (Point 0 0) (Point 1 1) "unit"))
           (moved (Segment-to-set segment (Point 5 5))))
      (write-line (show-segment segment))
      (write-line (show-segment moved)))
    (match (flip (Job (Point 1 2) (once (lambda () (write-line "worked")))))
      ((Job at work)
       (write-line (show-point at))
       (call-once work)))
    ;; A generic struct also stores its object argument by reference.
    (let ((pair (Pair (Point 7 8) "seven-eight")))
      (write-line (string-append (● pair second) " " (show-point (● pair first)))))
    (write-line (show-point (nearest (list (Point 3 1) (Point 2 9) (Point 5 5)))))
    (for-each (lambda (shape) (write-line (describe shape)))
              (list (Dot (Point 4 4)) (Line (Segment (Point 0 1) (Point 2 3) "l")) (Empty)))
    (write-line (show (● (Dot-at (Dot (Point 6 0))) x)))
    (let ((cursor (Cursor (Point 0 0) 0 (Point 1 1))))
      (set! (● cursor clicks) (+ (● cursor clicks) 1))
      (set! (● cursor last) (Point 2 2))
      (write-line (string-append (show (● cursor clicks))
                                 " "
                                 (show-point (● cursor home))
                                 " "
                                 (show-point (● cursor last))))
      (write-line (show-point (replace! (● cursor last) (Point 3 3))))
      (write-line (show-point (● cursor last))))
    ;; Accessors are functions too, and an Any holds a Point as itself.
    (write-line
     (string-join (map show (map (lambda (record) (● record x)) (list (Point 1 0) (Point 2 0))))
                  " "))
    (write-line (show-point (match (try-convert (type-convert (Point 9 9) Any) Point)
                              ((Ok value) value)
                              ((Err _) (panic "point round trip failed")))))
    (write-line (show-segment (handle Ask
                                  ((ask (lambda (resume) (resume 1))))
                                (build))))
    (unit)))
