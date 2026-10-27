(define-library (sample geometry)
  (export
   Point
   Point-x
   Point-y
   distance-squared
   swap!)
  (import
   (snail-core base))
  (begin

    (struct Point
      ((x I64)
       (y I64)))

    (: distance-squared (-> Point Point I64))
    (define (distance-squared a b)
      (let ((dx (- (Point-x a) (Point-x b))) (dy (- (Point-y a) (Point-y b))))
        (+ (* dx dx) (* dy dy))))

    ;; A macro whose template introduces `temporary`; it must not capture
    ;; the caller's variable of the same name.
    (define-syntax swap!
      (syntax-rules ()
        ((_ a b) (let ((temporary (ref-get a)))
                   (ref-set! a (ref-get b))
                   (ref-set! b temporary)))))

    ))
