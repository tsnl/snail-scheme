(import
 (snail core base)
 (snail core io)
 (prefix (sample geometry) geo:))

(define (main (out OutputPort)) (→ Unit)

  (let ((temporary (new geo:Point (x 1) (y 0))) (other (new geo:Point (x 2) (y 0))))
    (display out (geo:distance-squared (new geo:Point (x 0) (y 0)) (new geo:Point (x 3) (y 4))))
    (newline out)
    (geo:swap! temporary other)
    (display out (● temporary x))
    (newline out)
    (display out (● other x))
    (newline out)
    (match (new geo:Point (x 5) (y 6))
      ((geo:Point x y) (display out (+ x y)) (newline out)))
    (unit)))
