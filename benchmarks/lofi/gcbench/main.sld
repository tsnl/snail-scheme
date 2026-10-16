;; Canonical bare Lofi. See migration.json for source provenance.

(import (lofi base))

(def cddr (lambda (xs.2) (cdr (cdr xs.2))))

(def length
  (lambda (xs)
    (((lambda () (begin (def loop.6 (lambda (xs.1 n.4) (if (null? xs.1) n.4 (loop.6 (cdr xs.1) (+ n.4 (ann 1 I64)))))) loop.6)))
      xs
      (ann 0 I64))))

(define-extern native-input-i64 "benchmark" "input_i64" (-> I32 I64))

(define-extern native-input-f64 "benchmark" "input_f64" (-> I32 F64))

(define-extern barrier "benchmark" "barrier" (-> Bool))

(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))

(define-extern hide-f64 "benchmark" "hide_f64" (-> F64 F64))

(def classNode (datatype ()
  (Nil)
  (make-node-cells
    (left (Ref classNode) node.left-cell)
    (right (Ref classNode) node.right-cell)
    (i I64 node.i)
    (j I64 node.j))))

(def empty-node?
  (lambda (node.5) (match node.5 ((Nil) #t) ((make-node-cells left.1 right.1 i.7 j.1) #f))))

(def classNode? (lambda (node.4) (not (empty-node? node.4))))

(def make-node-raw (lambda (left right i.6 j) (make-node-cells (ref left) (ref right) i.6 j)))

(def node.left (lambda (node.3) (ref-get (node.left-cell node.3))))

(def node.right (lambda (node.2) (ref-get (node.right-cell node.2))))

(def node.left-set! (lambda (node.1 value.3) (ref-set! (node.left-cell node.1) value.3)))

(def node.right-set! (lambda (node value.2) (ref-set! (node.right-cell node) value.2)))

(def power-of-two
  (lambda (n.2)
    (((lambda () (begin (def loop.5 (lambda (n.3 value.1) (if (= n.3 (ann 0 I64)) value.1 (loop.5 (- n.3 (ann 1 I64)) (* value.1 (ann 2 I64)))))) loop.5)))
      n.2
      (ann 1 I64))))

(def min (lambda (a b) (if (< a b) a b)))

(def inexact (lambda (n.1) (i64->f64 n.1)))

(define-extern print-text "benchmark" "print_text" (-> I64 Unit))

(define-extern print-size "benchmark" "print_size" (-> I64 I64 Unit))

(define-extern print-construction "benchmark" "print_construction" (-> I64 I64 Unit))

(def hide (lambda (count.1 x) (hide-i64 x)))

(def run-benchmark2 (lambda (name thunk) (begin (print-text name) (print-text (ann 0 I64)) (thunk))))

(def PrintDiagnostics (lambda () (begin (print-text (ann 1 I64)) (print-text (ann 2 I64)) (print-text (ann 0 I64)))))

(def gcbench
  (lambda (kStretchTreeDepth)
    (begin
      (def TreeSize (lambda (i.5) (- (power-of-two (+ i.5 (ann 1 I64))) (ann 1 I64))))
      (def NumIters (lambda (i.4) (quotient (* (ann 2 I64) (TreeSize kStretchTreeDepth)) (TreeSize i.4))))
      ((lambda (kLongLivedTreeDepth) ((lambda (kArraySize) ((lambda (kMinTreeDepth) ((lambda (kMaxTreeDepth) ((lambda () (begin (def nil (Nil)) ((lambda (make-empty-node make-node) (begin (def Populate (lambda (iDepth.1 thisNode) (if (<= iDepth.1 (ann 0 I64)) (unit) ((lambda (iDepth.2) (begin (node.left-set! thisNode (make-empty-node)) (node.right-set! thisNode (make-empty-node)) (Populate iDepth.2 (node.left thisNode)) (Populate iDepth.2 (node.right thisNode)))) (- iDepth.1 (ann 1 I64)))))) (def MakeTree (lambda (iDepth) (if (<= iDepth (ann 0 I64)) (make-empty-node) (make-node (MakeTree (- iDepth (ann 1 I64))) (MakeTree (- iDepth (ann 1 I64))))))) (def TimeConstruction (lambda (depth) ((lambda (iNumIters) (begin (print-construction iNumIters depth) (print-text (ann 0 I64)) (run-benchmark2 (ann 4 I64) (lambda () (((lambda () (begin (def loop.4 (lambda (i.3) (if (>= i.3 iNumIters) (unit) (begin (Populate depth (make-empty-node)) (loop.4 (+ i.3 (ann 1 I64))))))) loop.4))) (ann 0 I64)))) (run-benchmark2 (ann 5 I64) (lambda () (((lambda () (begin (def loop.3 (lambda (i.2) (if (>= i.2 iNumIters) (unit) (begin (MakeTree depth) (loop.3 (+ i.2 (ann 1 I64))))))) loop.3))) (ann 0 I64)))))) (NumIters depth)))) (def run-benchmark-x (lambda () (begin (print-text (ann 3 I64)) (print-text (ann 0 I64)) (print-size (ann 0 I64) kStretchTreeDepth) (print-text (ann 0 I64)) (PrintDiagnostics) (run-benchmark2 (ann 6 I64) (lambda () (begin (MakeTree kStretchTreeDepth) (print-size (ann 1 I64) kLongLivedTreeDepth) (print-text (ann 0 I64)) ((lambda (longLivedTree) (begin (Populate kLongLivedTreeDepth longLivedTree) (print-size (ann 2 I64) kArraySize) (print-text (ann 0 I64)) ((lambda (array) (begin (((lambda () (begin (def loop.2 (lambda (i.1) (if (>= i.1 (quotient kArraySize (ann 2 I64))) (unit) (begin (vector-set! array i.1 (/ 1.0 (inexact (+ i.1 (ann 1 I64))))) (loop.2 (+ i.1 (ann 1 I64))))))) loop.2))) (ann 0 I64)) (PrintDiagnostics) (((lambda () (begin (def loop.1 (lambda (d) (if (> d kMaxTreeDepth) (unit) (begin (TimeConstruction d) (loop.1 (+ d (ann 2 I64))))))) loop.1))) kMinTreeDepth) (if ((lambda (value) (if value value ((lambda (n) (not (= (vector-ref array n) (/ 1.0 (inexact (+ n (ann 1 I64))))))) (min (ann 1000 I64) (- (quotient (vector-length array) (ann 2 I64)) (ann 1 I64)))))) (empty-node? longLivedTree)) (begin (print-text (ann 7 I64)) (print-text (ann 0 I64))) (unit)))) (make-vector kArraySize 0.0)))) (make-empty-node))))) (PrintDiagnostics)))) (run-benchmark-x))) (lambda () (make-node-raw nil nil (ann 0 I64) (ann 0 I64))) (lambda (l r) (make-node-raw l r (ann 0 I64) (ann 0 I64)))))))) kLongLivedTreeDepth)) (ann 4 I64))) (* (ann 4 I64) (TreeSize kLongLivedTreeDepth))))
        (- kStretchTreeDepth (ann 2 I64))))))

(def input0 (native-input-i64 (ann 0 I32)))

(def bench (-> I64 I64)
  (lambda (count)
    (begin
      (((lambda () (begin (def loop (lambda (i) (if (= i count) (unit) (begin (gcbench (hide count input0)) (loop (+ i (ann 1 I64))) (unit))))) loop)))
        (ann 0 I64))
      (ann 1 I64))))

(unit)
