(import
 (snail core base)
 (snail core io))

;; `record::field` reads a field of the record a name holds, and a longer
;; path reads through each record in turn.
(record Point
  ((x I64)
   (y I64)))

(record Segment
  ((from Point)
   (to Point)))

;; A record of functions is called by path.
(record Counter
  ((current (Fn → I64))
   (advance (Fn I64 → Unit))))

(define origin (→ Point) (new Point (x 0) (y 0)))

(define (length-squared (segment Segment)) (→ I64)
  (let ((dx (- segment::to::x segment::from::x))
        (dy (- segment::to::y segment::from::y)))
    (+ (* dx dx) (* dy dy))))

;; A template's path starts at the name the template binds.
(define-syntax swap-ends!
  (syntax-rules ()
    ((_ segment)
     (let ((held segment))
       (let ((first held::from))
         (set! held::from held::to)
         (set! held::to first))))))

(define (counter-over (cell Point)) (→ Counter)
  (new Counter
    (current (lambda () cell::x))
    (advance (lambda (by) (set! cell::x (+ cell::x by))))))

(define (main (out OutputPort)) (→ Unit)
  (let ((segment (new Segment (from (new Point (x 1) (y 2))) (to (new Point (x 4) (y 6)))))
        (counter (counter-over (new Point (x 0) (y 0)))))
    (write-line out (show (length-squared segment)))
    (set! segment::to::x 5)
    (write-line out (show segment::to::x))
    (swap-ends! segment)
    (write-line out (show segment::from::x))
    (counter::advance 3)
    (counter::advance 4)
    (write-line out (show (counter::current)))
    ;; A top-level value is a receiver like any name.
    (write-line out (show origin::x))
    ;; `●` reads a receiver that is not a name.
    (write-line out (show ((● (counter-over segment::to) current))))))
