(import
 (snail core base))

(record Point
  ((x I64)
   (y I64)))

(type Alias Point)

;; Each bad definition goes through the expander in the same compilation.
(define (duplicate) (→ Point) (new Point (x 1) (x 2) (y 3)))
(define (missing) (→ Point) (new Point (x 1)))
(define (unknown) (→ Point) (new Point (x 1) (z 2)))
(define (malformed) (→ Point) (new Point (x 1 2) (y 3)))
(define (positional) (→ Point) (Point 1 2))
(define (first-class) (→ Point) (let ((make Point)) (make 1 2)))
(define (aliased) (→ Point) (new Alias (x 1) (y 2)))
(define (enum-case) (→ (Option I64)) (new Some (value 1)))
