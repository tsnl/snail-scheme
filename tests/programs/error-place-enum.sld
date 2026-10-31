(import
 (snail core base))

;; An enum's case has no slot in the cell to write: the case accessor is
;; partial and the enum is a reference.
(enum Shape
  (Dot
   ((x I64)))
  (Empty))

(let ((cell (ref (Dot 1))))
  (set! (Dot-x (ref-get cell)) 2))
