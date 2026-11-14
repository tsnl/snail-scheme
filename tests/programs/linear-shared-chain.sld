(import
 (snail core base)
 (snail core io))

(record Resource
  ((name String)) )
(instance (Drop (!) Resource)
  (define (drop (value Resource)) (→ Unit)
    (match value ((Resource _) (unit)))))
(enum Chain
  (End)
  (Link ((node (Rc Node)))))
(record Node
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
  (let* ((chain (Link (rc (new Node (current (Some (new Resource (name "one"))))
                               (next (Link (rc (new Node
                                                 (current (Some (new Resource (name "two"))))
                                                 (next (End))))))))))
         (again chain))
    (run-chain chain)
    (run-chain again))
  (unit))
