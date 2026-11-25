(import
 (snail core base)
 (snail core io))

(record (Vec3 T)
  ((x T)
   (y T)
   (z T)))

(enum Shape
  (Circle ((radius I64)))
  (Rectangle ((width I64) (height I64)))
  (Dot))

(enum Color
  (Red)
  (Green)
  (Blue))

(define (area (shape Shape)) (→ I64)
  (match shape
    ((Circle r) (* 3 (* r r)))
    ((Rectangle w h) (* w h))
    ((Dot) 0)))

(define (color-name (color Color)) (→ String)
  (match color
    ((Red) "red")
    ((Green) "green")
    ((Blue) "blue")))

(define (sum (v (Vec3 I64))) (→ I64)
  (+ (● v x) (+ (● v y) (● v z))))

(define (main (out OutputPort)) (→ Unit)
  (display out (area (Circle 2)))
  (newline out)
  (display out (area (Rectangle 3 4)))
  (newline out)
  (display out (area (Dot)))
  (newline out)
  (write-line out (color-name (Green)))
  (display out (sum (new Vec3 (x 1) (y 2) (z 3))))
  (newline out)
  (display out (● (Vec3-y-set (new Vec3 (x 1) (y 2) (z 3)) 20) y))
  (newline out)
  (write out (map area (list (Dot) (Circle 1) (Rectangle 2 5))))
  (newline out)
  (unit))
