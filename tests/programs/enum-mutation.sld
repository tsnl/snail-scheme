(import
 (snail core base)
 (snail core io))

(record Radius
  ((value I64)))
(enum Shape (Circle ((radius Radius))) (Empty))
(record LinkData
  ((value I64)
   (next (Option Chain))))
(enum Chain (Link ((data LinkData))) (End))

(define (cycle) (→ Chain)
  (let* ((mut (unsafe-mut)) (data (new LinkData (value 3) (next (None)))) (link (Link data)))
    (set! mut (● data next) (Some link))
    link))

(define (main (mut Mut) (out OutputPort)) (→ Unit)
  (let* ((circle (Circle (new Radius (value 4)))) (alias circle))
    (match alias
      ((Circle radius) (set! mut (● radius value) 9))
      ((Empty) (panic "empty shape")))
    (match circle
      ((Circle radius)
       (write-line out (show (● radius value)))
       (write-line out (show (● radius value)))
       (set! mut (● radius value) 12))
      ((Empty) (panic "empty shape")))
    (match alias
      ((Circle radius) (write-line out (show (● radius value))))
      ((Empty) (panic "empty shape"))))
  (match (cycle)
    ((Link first)
     (set! mut (● first value) 21)
     (match (● first next)
       ((Some (Link same)) (write-line out (show (● same value))))
       (_ (panic "missing cycle")))
     (match (cycle)
       ((Link second) (write-line out (show (● second value))))
       ((End) (panic "empty chain"))))
    ((End) (panic "empty chain")))
  (unit))
