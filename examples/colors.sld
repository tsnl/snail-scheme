;; Structs, enums, typeclasses and pattern matching.
(import
 (snail-core base)
 (snail-core io))

(struct (Vec3 T)
  ((x T)
   (y T)
   (z T)))

(enum PrimaryColor
  (Red)
  (Green)
  (Blue))

(enum Color
  (Primary ((value PrimaryColor)))
  (Rgb ((value (Vec3 I64)))))

(typeclass (ToHex T)
  (: to-hex (-> T String)))

(: channel-hex (-> I64 String))
(define (channel-hex value)
  (let ((digits "0123456789abcdef"))
    (string (string-ref digits (quotient value 16))
            (string-ref digits (remainder value 16)))))

(instance (ToHex PrimaryColor)
  (define (to-hex color)
    (match color
      ((Red) "#ff0000")
      ((Green) "#00ff00")
      ((Blue) "#0000ff"))))

(instance (ToHex (Vec3 I64))
  (define (to-hex v)
    (string-append "#"
                   (channel-hex (Vec3-x v))
                   (channel-hex (Vec3-y v))
                   (channel-hex (Vec3-z v)))))

(instance (ToHex Color)
  (define (to-hex color)
    (match color
      ((Primary value) (to-hex value))
      ((Rgb value) (to-hex value)))))

(for-each (lambda (color) (write-line (to-hex color)))
          (list (Primary (Red)) (Rgb (Vec3 255 160 0)) (Primary (Blue))))
