(import
 (snail core base)
 (snail core io))

(struct Radius
  ((value I64)))
(enum Shape (Circle ((radius Radius))) (Empty))
(struct LinkData
  ((value I64)
   (next (Option Chain))))
(enum Chain (Link ((data LinkData))) (End))

(define (cycle) (→ Chain)
  (unsafe-total (lambda ()
                  (let* ((data (LinkData 3 (None))) (link (Link data)))
                    (set! (● data next) (Some link))
                    link))))

(define (main) (→ Unit) (! mut output-port)
  (let* ((circle (Circle (Radius 4))) (alias circle))
    (match alias
      ((Circle radius) (set! (● radius value) 9))
      ((Empty) (panic "empty shape")))
    (match circle
      ((Circle radius)
       (write-line (show (● radius value)))
       (write-line (show (replace! (● radius value) 12))))
      ((Empty) (panic "empty shape")))
    (match alias
      ((Circle radius) (write-line (show (● radius value))))
      ((Empty) (panic "empty shape"))))
  (match (cycle)
    ((Link first)
     (set! (● first value) 21)
     (match (● first next)
       ((Some (Link same)) (write-line (show (● same value))))
       (_ (panic "missing cycle")))
     (match (cycle)
       ((Link second) (write-line (show (● second value))))
       ((End) (panic "empty chain"))))
    ((End) (panic "empty chain")))
  (unit))
