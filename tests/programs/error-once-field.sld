(import
 (snail core base))

(record Bad
  ((work (Vector (FnOnce → Unit)))))

(define main
  (lambda ()
    (unit)
    (unit)))
