(import
 (lofi base)
 (lofi io)
 (only (lofi primitive) share-value shared-value))

(enum (Tree T)
  (Leaf
   ((value T)))
  (Branch
   ((left (Tree T))
    (right (Tree T)))))

(: sum (-> (Tree I64) I64))
(define (sum tree)
  (match tree
    ((Leaf value) value)
    ((Branch left right) (+ (sum left) (sum right)))))

(display (sum (shared-value (share-value (Branch (Leaf (ann 20 I64)) (Leaf (ann 22 I64)))))))
(newline)
