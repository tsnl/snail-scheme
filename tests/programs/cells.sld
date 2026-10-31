(import
 (snail core base)
 (snail core io))

;; `Ref` is the one struct with a mutable field: every other struct is a
;; value, and a program that changes one holds it in a cell. `set!` writes
;; a place, the cell's content or a chain of fields read from it, and
;; `replace!` swaps a value in and answers the old one. The content lies in
;; the cell: a cell of a Counter is one object with the counter's slots.
;; The book's ownership chapter includes the text between ANCHOR and
;; ANCHOR_END.
;; ANCHOR: counter
(struct Counter
  ((name String)
   (count I64)))

(: bump! (-> (Ref Counter) Unit ! mut))
(define (bump! counter)
  (set! (::count (ref-get counter)) (+ (::count (ref-get counter)) 1)))
;; ANCHOR_END: counter

;; Two names for one cell see the same writes.
(let* ((counter (ref (Counter "clicks" 0)))
       (same counter))
  (bump! counter)
  (bump! same)
  (write-line (string-append (::name (ref-get counter)) " " (show (::count (ref-get counter)))))
  (write-line (show (replace! (::count (ref-get same)) 10)))
  (write-line (show (::count (ref-get counter)))))

;; A place reaches through nested structs to one slot of the cell.
(struct Point
  ((x I64)
   (y I64)))

(struct Cursor
  ((home Point)
   (last Point)))

(let ((cursor (ref (Cursor (Point 0 0) (Point 1 1)))))
  (set! (::last::x (ref-get cursor)) 5)
  (set! (::home (ref-get cursor)) (Point 2 3))
  (write-line (string-append (show (::home::y (ref-get cursor)))
                             " "
                             (show (::last::x (ref-get cursor)))
                             " "
                             (show (::last::y (ref-get cursor)))))
  (match (replace! (::home (ref-get cursor)) (Point 9 9))
    ((Point x y) (write-line (string-append (show x) "," (show y)))))
  (write-line (show (::home::x (ref-get cursor)))))

;; A cell of a number is written whole; `ref-set!` is `set!` of the content.
(let ((cell (ref 41)))
  (set! (ref-get cell) (+ (ref-get cell) 1))
  (ref-set! cell (+ (ref-get cell) 1))
  (write-line (show (ref-get cell))))
