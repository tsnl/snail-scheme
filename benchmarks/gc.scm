;; Retain a small ring of cyclic trees while replacing older trees with garbage.
;;
;; Parent links make the garbage cyclic, and retained trees exercise precise
;; tracing across both forward and backward links. Verification follows only
;; child links, checks parent identity, and sums every retained node's label.
;; Explicit collections make pause measurements useful even for short runs.
(import (scheme base) (scheme write) (scheme time) (scheme process-context)
        (snail-scheme runtime))

(define tree-depth 6)
(define retained-trees 8)
(define allocation-rounds 128)

;; A node is #(label left right parent). Labels form the familiar heap-indexed
;; binary tree: children of n are 2*n and 2*n+1. A missing child is #f.

(define (make-tree depth label parent)
  (let ((node (vector label #f #f parent)))
    (when (> depth 0)
      (vector-set! node 1 (make-tree (- depth 1) (* label 2) node))
      (vector-set! node 2 (make-tree (- depth 1) (+ (* label 2) 1) node)))
    node))

(define (verify-node node parent depth label)
  (unless (and (vector? node) (= (vector-length node) 4))
    (error "collector lost a tree node"))
  (unless (eq? (vector-ref node 3) parent)
    (error "collector lost a parent link"))
  (require-equal (vector-ref node 0) label "collector changed a node label")
  (when (= depth 0)
    (unless (and (not (vector-ref node 1)) (not (vector-ref node 2)))
      (error "collector changed a leaf"))))

(define (verify-tree node parent depth label)
  (verify-node node parent depth label)
  (if (= depth 0)
      label
      (+ label
         (verify-tree (vector-ref node 1) node (- depth 1) (* label 2))
         (verify-tree (vector-ref node 2) node (- depth 1) (+ (* label 2) 1)))))

;; The arithmetic-series oracle never constructs or walks a tree. At level k,
;; labels are the consecutive integers label*2^k through (label+1)*2^k-1.

(define (level-sum label width)
  (+ (* label width width) (quotient (* width (- width 1)) 2)))

(define (expected-tree-sum depth label)
  (let loop ((level 0) (width 1) (sum 0))
    (if (> level depth)
        sum
        (loop (+ level 1) (* width 2) (+ sum (level-sum label width))))))

(define (require-equal actual expected description)
  (unless (= actual expected)
    (error description actual expected)))

(define (verify-retained-tree tree index)
  (let* ((label (+ (- allocation-rounds retained-trees) index 1))
         (sum (verify-tree tree #f tree-depth label)))
    (require-equal sum (expected-tree-sum tree-depth label) "collector changed a retained tree")
    sum))

(define (verify-ring ring)
  (let loop ((index 0) (checksum 0))
    (if (= index (vector-length ring))
        checksum
        (loop (+ index 1)
              (+ checksum (verify-retained-tree (vector-ref ring index) index))))))

(define (fill-ring! ring)
  (let loop ((round 0))
    (when (< round allocation-rounds)
      (vector-set! ring (modulo round retained-trees)
                   (make-tree tree-depth (+ round 1) #f))
      (when (= (modulo (+ round 1) 32) 0) (collect-garbage))
      (loop (+ round 1)))))

(define (workload)
  (let ((ring (make-vector retained-trees #f)))
    (fill-ring! ring)
    (collect-garbage)
    (verify-ring ring)))

(define (expected-answer)
  (let loop ((label (+ (- allocation-rounds retained-trees) 1)) (sum 0))
    (if (> label allocation-rounds)
        sum
        (loop (+ label 1) (+ sum (expected-tree-sum tree-depth label))))))

(define (check-trees)
  (for-each
   (lambda (depth)
     (let ((tree (make-tree depth 3 #f)))
       (collect-garbage)
       (require-equal (verify-tree tree #f depth 3) (expected-tree-sum depth 3)
                      "incorrect cyclic tree")))
   '(0 1 2 3)))

(define (repeat-work count expected)
  (let loop ((remaining count) (checksum 0))
    (if (= remaining 0)
        checksum
        (let ((answer (workload)))
          (require-equal answer expected "incorrect cyclic-tree result")
          (loop (- remaining 1) (+ checksum answer))))))

(define (positive-count text)
  (let ((count (string->number text)))
    (unless (and (exact-integer? count) (> count 0))
      (error "repeat count must be a positive integer" text))
    count))

(define (repetitions)
  (let ((arguments (cdr (command-line))))
    (cond ((null? arguments) 1)
          ((null? (cdr arguments)) (positive-count (car arguments)))
          (else (error "usage: gc [REPETITIONS]")))))

(define (elapsed-microseconds start finish)
  (quotient (* (- finish start) 1000000) (jiffies-per-second)))

(define (write-milliseconds microseconds)
  (display (quotient microseconds 1000))
  (display ".")
  (let ((fraction (modulo microseconds 1000)))
    (when (< fraction 100) (display "0"))
    (when (< fraction 10) (display "0"))
    (display fraction)))

(define (report-gc before after)
  (display "; GC: ")
  (write (- (vector-ref after 0) (vector-ref before 0)))
  (display " collections, ")
  (write-milliseconds (quotient (- (vector-ref after 1) (vector-ref before 1)) 1000))
  (display " ms"))

(define (report checksum elapsed count before after)
  (display "GC: retained cyclic trees") (newline)
  (display "checksum: ") (write checksum) (newline)
  (display "elapsed: ") (write-milliseconds elapsed)
  (display " ms; repetitions: ") (write count)
  (report-gc before after) (newline))

(define (check-collection before after)
  (unless (and (> (vector-ref after 0) (vector-ref before 0))
               (> (vector-ref after 4) (vector-ref before 4)))
    (error "GC workload must collect and reclaim objects")))

(define (measure count expected)
  (let* ((start (current-jiffy))
         (before (gc-statistics))
         (checksum (repeat-work count expected))
         (after (gc-statistics))
         (finish (current-jiffy)))
    (require-equal checksum (* count expected) "incorrect cyclic-tree checksum")
    (check-collection before after)
    (report checksum (elapsed-microseconds start finish) count before after)))

(define (main)
  (check-trees)
  (collect-garbage)
  (let ((count (repetitions)))
    (measure count (expected-answer))))

(main)
