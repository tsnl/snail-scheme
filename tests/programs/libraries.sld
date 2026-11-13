(import
 (snail core base)
 (snail core io)
 (prefix (sample geometry) geo:))

(define (main) (→ Unit) (! mut output-port)

  (let ((temporary (geo:Point 1 0)) (other (geo:Point 2 0)))
    (display (geo:distance-squared (geo:Point 0 0) (geo:Point 3 4)))
    (newline)
    (geo:swap! temporary other)
    (display (● temporary x))
    (newline)
    (display (● other x))
    (newline)
    (match (geo:Point 5 6)
      ((geo:Point x y) (display (+ x y)) (newline)))
    (unit)))
