(import
 (snail core base)
 (snail core io))

;; A search stops at the first value it finds: `found` hands the value to
;; its handler, whose implementation drops `resume`, so nothing after the
;; operation runs, in the search or in the frames that called it.
(effect Found
  ((ctl found (dyn (Fn I64 → Unit)))))

(enum Tree
  (Leaf)
  (Node
   ((left Tree)
    (value I64)
    (right Tree))))

(define tree (→ Tree)
  (Node (Node (Leaf) 3 (Node (Leaf) 8 (Leaf))) 5 (Node (Node (Leaf) 12 (Leaf)) 7 (Leaf))))

;; An in-order walk that reports each value it passes, so the output shows
;; where the walk stopped.
(define (walk (wanted (dyn (Fn I64 → Bool))) (tree Tree)) (→ Unit) (! Found console)
  (match tree
    ((Leaf) (unit))
    ((Node left value right)
     (walk wanted left)
     (write-line (string-append "visit " (show value)))
     (when (wanted value) (found value))
     (walk wanted right))))

(define (first-where (wanted (dyn (Fn I64 → Bool)))) (→ I64) (! console)
  (handle Found ((found (lambda (value resume) (drop resume) value)))
    (walk wanted tree)
    -1))

(write-line (string-append "first above 6: " (show (first-where (lambda (value) (> value 6))))))
(write-line (string-append "first above 20: " (show (first-where (lambda (value) (> value 20))))))

;; Operands that ran before the operation keep their effects; the call
;; they were for never happens.
(define (sum (tree Tree)) (→ I64) (! Found)
  (match tree
    ((Leaf) 0)
    ((Node left value right)
     (+ (sum left) (+ (if (= value 12) (begin (found value) 0) value) (sum right))))))

(write-line (string-append "sum: "
                           (show (handle Found ((found
                                                 (lambda (value resume) (drop resume) (- 0 value))))
                                   (sum tree)))))

;; A `FnOnce` held across the operation is dropped with the frame that held
;; it, and never runs.
(define (guarded (items (List I64))) (→ I64) (! console)
  (handle Found ((found (lambda (value resume) (drop resume) value)))
    (let ((cleanup (once (lambda () (write-line "cleanup ran")))))
      (for-each (lambda (item) (when (< item 0) (found item))) items)
      (cleanup)
      0)))

(write-line (string-append "guarded: " (show (guarded (list 1 2 3)))))
(write-line (string-append "guarded: " (show (guarded (list 1 -2 3)))))
