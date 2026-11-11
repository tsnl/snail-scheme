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

(define (bump! (counter (Ref Counter))) (→ Unit) (! mut)
  (set! (● (ref-get counter) count) (+ (● (ref-get counter) count) 1)))
;; ANCHOR_END: counter

;; Two names for one cell see the same writes.
(let* ((counter (ref (Counter "clicks" 0)))
       (same counter))
  (bump! counter)
  (bump! same)
  (write-line (string-append (● (ref-get counter) name) " " (show (● (ref-get counter) count))))
  (write-line (show (replace! (● (ref-get same) count) 10)))
  (write-line (show (● (ref-get counter) count))))

;; A place reaches through nested structs to one slot of the cell.
(struct Point
  ((x I64)
   (y I64)))

(struct Cursor
  ((home Point)
   (last Point)))

(let ((cursor (ref (Cursor (Point 0 0) (Point 1 1)))))
  (set! (● (ref-get cursor) last x) 5)
  (set! (● (ref-get cursor) home) (Point 2 3))
  (write-line (string-append (show (● (ref-get cursor) home y))
                             " "
                             (show (● (ref-get cursor) last x))
                             " "
                             (show (● (ref-get cursor) last y))))
  (match (replace! (● (ref-get cursor) home) (Point 9 9))
    ((Point x y) (write-line (string-append (show x) "," (show y)))))
  (write-line (show (● (ref-get cursor) home x))))

;; A cell of a number is written whole; `ref-set!` is `set!` of the content.
(let ((cell (ref 41)))
  (set! (ref-get cell) (+ (ref-get cell) 1))
  (ref-set! cell (+ (ref-get cell) 1))
  (write-line (show (ref-get cell))))
