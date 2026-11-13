(import
 (snail core base)
 (snail core io))

(struct Resource
  ((name String)) )
(instance (Drop (!) Resource)
  (define (drop (value Resource)) (→ Unit)
    (match value ((Resource _) (unit)))))
(enum Chain
  (End)
  (Link ((node (Rc Node)))))
(struct Node
  ((current (Option Resource))
   (next Chain)))

(define (run-chain (chain Chain)) (→ Unit) (! mut output-port)
  (match chain
    ((End) (unit))
    ((Link node)
     (match (replace! (● node current) (None))
       ((Some (Resource name)) (write-line name))
       ((None) (write-line "gone")))
     (run-chain (● node next)))))

(define (main) (→ Unit) (! mut output-port)
  (let* ((chain (Link (rc (Node (Some (Resource "one"))
                                (Link (rc (Node (Some (Resource "two")) (End))))))))
         (again chain))
    (run-chain chain)
    (run-chain again))
  (unit))
