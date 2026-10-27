(import
 (snail-core base)
 (snail-core io))

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

(: area (-> Shape I64))
(define (area shape)
  (match shape
    ((Circle r) (* 3 (* r r)))
    ((Rectangle w h) (* w h))
    ((Dot) 0)))

(: color-name (-> Color String))
(define (color-name color)
  (match color
    ((Red) "red")
    ((Green) "green")
    ((Blue) "blue")))

(: sum (-> (Vec3 I64) I64))
(define (sum v)
  (+ (Vec3-x v) (+ (Vec3-y v) (Vec3-z v))))

(display (area (Circle 2)))
(newline)
(display (area (Rectangle 3 4)))
(newline)
(display (area (Dot)))
(newline)
(write-line (color-name (Green)))
(display (sum (Vec3 1 2 3)))
(newline)
(display (Vec3-y (Vec3-y-set (Vec3 1 2 3) 20)))
(newline)
(display (map area (list (Dot) (Circle 1) (Rectangle 2 5))))
(newline)
