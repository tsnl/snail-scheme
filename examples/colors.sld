;; Structs, enums, typeclasses and pattern matching.
(import
 (snail core base)
 (snail core io))

(record (Vec3 T)
  ((x T)
   (y T)
   (z T)))

(enum Primary-color
  (Red)
  (Green)
  (Blue))

(enum Color
  (Primary ((value Primary-color)))
  (Rgb ((value (Vec3 I64)))))

(typeclass (To-hex T)
  (declare (to-hex (value T)) (→ String)))

(define (channel-hex (value I64)) (→ String)
  (let ((digits "0123456789abcdef"))
    (string (string-ref digits (quotient value 16)) (string-ref digits (remainder value 16)))))

(instance (To-hex Primary-color)
  (define (to-hex (color Primary-color)) (→ String)
    (match color
      ((Red) "#ff0000")
      ((Green) "#00ff00")
      ((Blue) "#0000ff"))))

(instance (To-hex (Vec3 I64))
  (define (to-hex (v (Vec3 I64))) (→ String)

    (string-append "#" (channel-hex (● v x)) (channel-hex (● v y)) (channel-hex (● v z)))))

(instance (To-hex Color)
  (define (to-hex (color Color)) (→ String)
    (match color
      ((Primary value) (to-hex value))
      ((Rgb value) (to-hex value)))))

(define (main) (→ Unit) (! Output-port)
  (for-each (lambda (color) (write-line (to-hex color)))
            (list (Primary (Red)) (Rgb (new Vec3 (x 255) (y 160) (z 0))) (Primary (Blue))))
  (unit))
