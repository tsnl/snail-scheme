(import
 (snail core base)
 (snail core io)
 (prefix (sample geometry) geo:))

(define (main) (→ Unit) (! mut output-port)

  (let ((temporary (new geo:Point (x 1) (y 0))) (other (new geo:Point (x 2) (y 0))))
    (display (geo:distance-squared (new geo:Point (x 0) (y 0)) (new geo:Point (x 3) (y 4))))
    (newline)
    (geo:swap! temporary other)
    (display (● temporary x))
    (newline)
    (display (● other x))
    (newline)
    (match (new geo:Point (x 5) (y 6))
      ((geo:Point x y) (display (+ x y)) (newline)))
    (unit)))
