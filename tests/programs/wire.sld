(import
 (snail-core base)
 (snail-core io)
 (snail-core wire))

(struct Point
  ((x I64)
   (y I64))
  (deriving Serialize Deserialize))

(enum (Tree T)
  (Leaf)
  (Node ((left (Tree T)) (value T) (right (Tree T))))
  (deriving Serialize Deserialize))

(enum Shape
  (Circle ((center Point) (radius F64)))
  (Polygon ((points (List Point))))
  (deriving Serialize Deserialize))

(: tree-sum (-> (Tree I64) I64))
(define (tree-sum tree)
  (match tree
    ((Leaf) 0)
    ((Node left value right) (+ (tree-sum left) (+ value (tree-sum right))))))

(define tree (Node (Node (Leaf) 1 (Leaf)) 2 (Node (Leaf) 3 (Leaf))))
(define bytes (serialize tree))
(display (vector-length bytes))
(newline)
(display (tree-sum (ann (deserialize bytes) (Tree I64))))
(newline)
(define shapes (list (Circle (Point 1 2) 0.5) (Polygon (list (Point 0 0) (Point 10 -4)))))
(define copy (ann (deserialize (serialize shapes)) (List Shape)))
(match copy
  ((Cons (Circle (Point x y) r) (Cons (Polygon (Cons _ (Cons (Point px py) _))) _))
   (display (list x y px py))
   (newline)
   (display r)
   (newline))
  (_ (write-line "mismatch")))
(write-line (ann (deserialize (serialize "héllo")) String))
(display (ann (deserialize (serialize (list -1 300 -70000))) (List I64)))
(newline)
