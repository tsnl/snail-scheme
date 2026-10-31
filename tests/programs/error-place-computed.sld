(import
 (snail core base))

;; A declared instance computes its field, so there is nothing to write.
(struct Circle
  ((radius I64)))

(instance (::x Circle I64)
  (define (::x circle)
    (* 2 (Circle-radius circle))))

(let ((cell (ref (Circle 1))))
  (set! (::x (ref-get cell)) 4))
