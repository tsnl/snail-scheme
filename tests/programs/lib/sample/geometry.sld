(define-library (sample geometry)
  (export
   Point
   distance-squared
   swap!)
  (import
   (snail core base))
  (begin

    (record Point
      ((x I64)
       (y I64)))

    (define (distance-squared (a Point) (b Point)) (→ I64)
      (let ((dx (- (● a x) (● b x))) (dy (- (● a y) (● b y))))
        (+ (* dx dx) (* dy dy))))

    ;; A macro whose template introduces `temporary`; it must not capture
    ;; the caller's variable of the same name.
    (define-syntax swap!
      (syntax-rules ()
        ((_ a b) (let ((temporary (● a x)))
                   (set! (● a x) (● b x))
                   (set! (● b x) temporary)))))

    ))
