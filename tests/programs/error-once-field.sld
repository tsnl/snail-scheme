(import
 (snail core base))

(struct Bad
  ((work (Vector (FnOnce → Unit)))))

(define main
  (lambda ()
    (unit)
    (unit)))
