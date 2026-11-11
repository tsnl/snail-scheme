(import
 (snail core base)
 (snail core io))

(struct (Vec3 T)
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

(: area (impl (Fn Shape -> I64)))
(define (area shape)
  (match shape
    ((Circle r) (* 3 (* r r)))
    ((Rectangle w h) (* w h))
    ((Dot) 0)))

(: color-name (impl (Fn Color -> String)))
(define (color-name color)
  (match color
    ((Red) "red")
    ((Green) "green")
    ((Blue) "blue")))

(: sum (impl (Fn (Vec3 I64) -> I64)))
(define (sum v)
  (+ (::x v) (+ (::y v) (::z v))))

(display (area (Circle 2)))
(newline)
(display (area (Rectangle 3 4)))
(newline)
(display (area (Dot)))
(newline)
(write-line (color-name (Green)))
(display (sum (Vec3 1 2 3)))
(newline)
(display (::y (Vec3-y-set (Vec3 1 2 3) 20)))
(newline)
(display (map area (list (Dot) (Circle 1) (Rectangle 2 5))))
(newline)
