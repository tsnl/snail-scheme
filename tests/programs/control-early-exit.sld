(import
 (snail core base)
 (snail core io))

;; A search stops at the first value it finds: `found` hands the value to
;; its handler, whose implementation never calls `resume`, so nothing after
;; the operation runs, in the search or in the frames that called it.
(effect Found
  ((ctl found (Fn I64 → Unit))))

(enum Tree
  (Leaf)
  (Node
   ((left Tree)
    (value I64)
    (right Tree))))

(define (tree) (→ Tree)
  (Node (Node (Leaf) 3 (Node (Leaf) 8 (Leaf))) 5 (Node (Node (Leaf) 12 (Leaf)) 7 (Leaf))))

;; An in-order walk that reports each value it passes, so the output shows
;; where the walk stopped.
(define (walk (wanted (Fn I64 → Bool)) (tree Tree)) (→ Unit) (! Found output-port)
  (match tree
    ((Leaf) (unit))
    ((Node left value right)
     (walk wanted left)
     (write-line (string-append "visit " (show value)))
     (when (wanted value) (found value))
     (walk wanted right))))

(define (first-where (wanted (Fn I64 → Bool))) (→ I64) (! output-port)
  (handle Found ((found (lambda (value resume) value)))
    (walk wanted (tree))
    -1))

;; Operands that ran before the operation keep their effects; the call
;; they were for never happens.
(define (sum (tree Tree)) (→ I64) (! Found)
  (match tree
    ((Leaf) 0)
    ((Node left value right)
     (+ (sum left) (+ (if (= value 12) (begin (found value) 0) value) (sum right))))))

;; A procedure held across the operation stays in the frame that held it,
;; which nothing resumes, so it never runs.
(define (guarded (items (List I64))) (→ I64) (! output-port)
  (handle Found ((found (lambda (value resume) value)))
    (let ((cleanup (lambda () (write-line "cleanup ran"))))
      (for-each (lambda (item) (when (< item 0) (found item))) items)
      (cleanup)
      0)))

(define (main) (→ Unit) (! output-port)
  (write-line (string-append "first above 6: " (show (first-where (lambda (value) (> value 6))))))
  (write-line
   (string-append "first above 20: " (show (first-where (lambda (value) (> value 20))))))
  (write-line (string-append "sum: "
                             (show (handle Found ((found
                                                   (lambda (value resume)
                                                     (- 0 value))))
                                     (sum (tree))))))
  (write-line (string-append "guarded: " (show (guarded (list 1 2 3)))))
  (write-line (string-append "guarded: " (show (guarded (list 1 -2 3)))))
  (unit))
