(import (lofi base))
(def Tree (datatype ( T) (leaf (value T)) (branch (left (Tree T)) (right (Tree T)))))

(def first (All (A) (-> (Tree A) A))
     (lambda (tree) (match tree ((leaf value) value) ((branch left right) (first left)))))
(first (branch (leaf (ann 11 I64)) (leaf (ann 13 I64))))
