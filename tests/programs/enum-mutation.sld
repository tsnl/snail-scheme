(import
 (snail core base)
 (snail core io))

(enum Shape
  (Circle ((radius I64)))
  (Empty))

(enum Chain
  (Link ((value I64) (next (Option Chain))))
  (End))

(define cycle (→ Chain)
  (unsafe-total
   (lambda ()
     (let ((link (Link 3 (None))))
       (Link-next-set! link (Some link))
       link))))

(define (main) (→ Unit) (! mut output-port)
  (let* ((circle (Circle 4)) (alias circle))
    (Circle-radius-set! alias 9)
    (write-line (show (Circle-radius circle)))
    (write-line (show (Circle-radius-replace! circle 12)))
    (write-line (show (Circle-radius alias))))
  (let ((first cycle) (second cycle))
    (Link-value-set! first 21)
    (match (Link-next first)
      ((Some same) (write-line (show (Link-value same))))
      ((None) (panic "missing cycle")))
    (write-line (show (Link-value second))))
  (unit))
