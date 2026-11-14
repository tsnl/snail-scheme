(import
 (snail core base))

;; Matching moves the fields out, and a wildcard would discard one.
(record Job
  ((work (FnOnce → Unit))))

(define main
  (lambda ()
    (match (new Job (work (once (lambda () (unit)))))
      ((Job _) (unit)))
    (unit)))
