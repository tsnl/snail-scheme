(import
 (snail core base))

;; Matching moves the fields out, and a wildcard would discard one.
(struct Job
  ((work (Once (-> Unit)))))

(match (Job (once (lambda () (unit))))
  ((Job _) (unit)))
