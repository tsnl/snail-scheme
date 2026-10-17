(import
 (lofi base))
;; Gcbench's top-down writes and bottom-up construction with explicit Ref
;; child slots. One shared Nil replaces the original numeric zero sentinel.
(def Tree (datatype ()
            (Nil)
            (Node
             (left (Ref Tree) node-left)
             (right (Ref Tree) node-right)
             (i I64)
             (j I64))))
(def empty
     (Nil))
(def make-empty-node
     (lambda () (Node (ref empty) (ref empty) (ann 0 I64) (ann 0 I64))))
(def make-node
     (lambda (left right) (Node (ref left) (ref right) (ann 0 I64) (ann 0 I64))))
(def populate
     (lambda (depth node)
       (if (<= depth (ann 0 I64))
           (unit)
           (begin (let next (- depth (ann 1 I64)))
                  (begin
                    (ref-set! (node-left node) (make-empty-node))
                    (ref-set! (node-right node) (make-empty-node))
                    (populate next (ref-get (node-left node)))
                    (populate next (ref-get (node-right node))))))))
(def make-tree
     (lambda (depth)
       (if (<= depth (ann 0 I64))
           (make-empty-node)
           (make-node (make-tree (- depth (ann 1 I64))) (make-tree (- depth (ann 1 I64)))))))
(def size
     (lambda (tree)
       (match tree ((Nil) (ann 0 I64))
              ((Node left right i j) (+ (ann 1 I64) (+ (size (ref-get left)) (size (ref-get right))))))))
(def top
     (make-empty-node))
(populate (ann 4 I64) top)
(+ (size top) (size (make-tree (ann 4 I64))))
