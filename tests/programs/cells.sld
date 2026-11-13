(import
 (snail core base)
 (snail core io))

;; Structs are shared heap objects. Every field is mutable; writes perform
;; mut, while reads are pure. A nested path reaches the child object itself.
;; The book includes the example between ANCHOR and ANCHOR_END.
;; ANCHOR: counter
(struct Counter
  ((name String)
   (count I64)))

(define (bump! (counter Counter)) (→ Unit) (! mut)
  (set! (● counter count) (+ (● counter count) 1)))

;; A path reaches through nested structs to one field.
(struct Point
  ((x I64)
   (y I64)))

(struct Cursor
  ((home Point)
   (last Point)))

(define main
  (lambda ()
    ;; ANCHOR_END: counter

    ;; Two names for one object see the same writes.
    (let* ((counter (Counter "clicks" 0))
           (same counter))
      (bump! counter)
      (bump! same)
      (write-line (string-append (● counter name) " " (show (● counter count))))
      (write-line (show (replace! (● same count) 10)))
      (write-line (show (● counter count))))
    (let ((cursor (Cursor (Point 0 0) (Point 1 1))))
      (set! (● cursor last x) 5)
      (set! (● cursor home) (Point 2 3))
      (write-line (string-append (show (● cursor home y))
                                 " "
                                 (show (● cursor last x))
                                 " "
                                 (show (● cursor last y))))
      (match (replace! (● cursor home) (Point 9 9))
        ((Point x y) (write-line (string-append (show x) "," (show y)))))
      (write-line (show (● cursor home x))))
    (let ((counter (Counter "scalar" 41)))
      (set! (● counter count) (+ (● counter count) 1))
      (set! (● counter count) (+ (● counter count) 1))
      (write-line (show (● counter count))))
    (unit)))
