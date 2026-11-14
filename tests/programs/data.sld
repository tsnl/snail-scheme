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

(define (main) (→ Unit) (! output-port)
  (display (area (Circle 2)))
  (newline)
  (display (area (Rectangle 3 4)))
  (newline)
  (display (area (Dot)))
  (newline)
  (write-line (color-name (Green)))
  (display (sum (new Vec3 (x 1) (y 2) (z 3))))
  (newline)
  (display (● (Vec3-y-set (new Vec3 (x 1) (y 2) (z 3)) 20) y))
  (newline)
  (write (map area (list (Dot) (Circle 1) (Rectangle 2 5))))
  (newline)
  (unit))
