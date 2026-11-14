(import
 (snail core base))

;; A field operation on a linear record works in place, and a temporary has
;; no place to stay in: its work item would be left with no owner.
(record Task
  ((work (FnOnce → Unit))
   (tries I64)))

(define main
  (lambda ()
    (● (new Task (work (once (lambda () (unit)))) (tries 0)) tries)
    (unit)))
