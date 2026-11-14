(import
 (snail core base)
 (snail core io))

;; Structs are shared heap objects. Every field is mutable; writes perform
;; mut, while reads are pure. A nested path reaches the child object itself.
;; The book includes the example between ANCHOR and ANCHOR_END.
;; ANCHOR: counter
(record Counter
  ((name String)
   (count I64)))

(define (bump! (counter Counter)) (→ Unit) (! mut)
  (set! (● counter count) (+ (● counter count) 1)))

;; A path reaches through nested structs to one field.
(record Point
  ((x I64)
   (y I64)))

(record Cursor
  ((home Point)
   (last Point)))

(define (main) (→ Unit) (! mut output-port)

  ;; ANCHOR_END: counter

  ;; Two names for one object see the same writes.
  (let* ((counter (new Counter (name "clicks") (count 0)))
         (same counter))
    (bump! counter)
    (bump! same)
    (write-line (string-append (● counter name) " " (show (● counter count))))
    (write-line (show (● same count)))
    (set! (● same count) 10)
    (write-line (show (● counter count))))
  (let ((cursor (new Cursor (home (new Point (x 0) (y 0))) (last (new Point (x 1) (y 1))))))
    (set! (● cursor last x) 5)
    (set! (● cursor home) (new Point (x 2) (y 3)))
    (write-line (string-append (show (● cursor home y))
                               " "
                               (show (● cursor last x))
                               " "
                               (show (● cursor last y))))
    (match (● cursor home)
      ((Point x y) (write-line (string-append (show x) "," (show y)))))
    (set! (● cursor home) (new Point (x 9) (y 9)))
    (write-line (show (● cursor home x))))
  (let ((counter (new Counter (name "scalar") (count 41))))
    (set! (● counter count) (+ (● counter count) 1))
    (set! (● counter count) (+ (● counter count) 1))
    (write-line (show (● counter count))))
  (unit))
