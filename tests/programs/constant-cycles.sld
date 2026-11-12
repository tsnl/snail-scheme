(import
 (snail core base)
 (snail core io))

(struct Link
  ((value I64)
   (next (Option Link))))

(struct Branch
  ((value I64)
   (children (Array (Option Branch)))))

(define ring (→ Link)
  (unsafe-total
   (lambda ()
     (let ((node (Link 3 (None))))
       (set! (● node next) (Some node))
       node))))

(define tree (→ Branch)
  (unsafe-total
   (lambda ()
     (let ((node (Branch 4 (make-array 1 (None)))))
       (array-set! (● node children) 0 (Some node))
       node))))

(define (main) (→ Unit) (! mut output-port)
  (let ((first ring) (second ring))
    (set! (● first value) 9)
    (match (● first next)
      ((Some next) (write-line (show (● next value))))
      ((None) (panic "missing cycle")))
    (match (● second next)
      ((Some next) (write-line (show (● next value))))
      ((None) (panic "missing cycle"))))
  (let ((first tree) (second tree))
    (set! (● first value) 8)
    (match (array-ref (● first children) 0)
      ((Some child) (write-line (show (● child value))))
      ((None) (panic "missing array cycle")))
    (match (array-ref (● second children) 0)
      ((Some child) (write-line (show (● child value))))
      ((None) (panic "missing array cycle"))))
  (unit))
