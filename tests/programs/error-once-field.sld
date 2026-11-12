(import
 (snail core base))

(struct Bad
  ((work (Array (FnOnce → Unit)))))

(define main
  (lambda ()
    (unit)
    (unit)))
