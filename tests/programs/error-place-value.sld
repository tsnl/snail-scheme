(import
 (snail core base))

;; As a value, a field operation consumes the record it is applied to,
;; which would leave a linear record's work item with no owner.
(struct Task
  ((work (dyn (FnOnce -> Unit)))
   (tries I64)))

(: tries (impl (Fn (dyn (Fn Task -> I64)) -> (dyn (Fn Task -> I64)))))
(define (tries read)
  read)

(tries ::tries)
