(import
 (snail core base)
 (snail core io))

(record Link
  ((value I64)
   (next (Option Link))))

(record Branch
  ((value I64)
   (children (Array (Option Branch)))))

(define (ring) (→ Link)
  (let ((node (new Link (value 3) (next (None)))))
    (set! (● node next) (Some node))
    node))

(define (tree) (→ Branch)
  (let ((node (new Branch (value 4) (children (make-array 1 (None))))))
    (array-set! (● node children) 0 (Some node))
    node))

(define (main (out OutputPort)) (→ Unit)
  (let ((first (ring)) (second (ring)))
    (set! (● first value) 9)
    (match (● first next)
      ((Some next) (write-line out (show (● next value))))
      ((None) (panic "missing cycle")))
    (match (● second next)
      ((Some next) (write-line out (show (● next value))))
      ((None) (panic "missing cycle"))))
  (let ((first (tree)) (second (tree)))
    (set! (● first value) 8)
    (match (array-ref (● first children) 0)
      ((Some child) (write-line out (show (● child value))))
      ((None) (panic "missing array cycle")))
    (match (array-ref (● second children) 0)
      ((Some child) (write-line out (show (● child value))))
      ((None) (panic "missing array cycle"))))
  (unit))
