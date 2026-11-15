(import
 (snail core base)
 (snail core io))

;; A record's field is read by path; its accessor name is reserved, so a
;; read through it is refused and a definition of it is a duplicate.
(record Point
  ((x I64)))

(define main
  (lambda ()
    (write-line (show (Point-x (new Point (x 1)))))
    (unit)))
