(import
 (snail core base))

;; As a value, a field operation consumes the record it is applied to,
;; which would leave a linear record's work item with no owner.
(struct Task
  ((work (FnOnce Unit))
   (tries mut I64)))

(: tries (-> (-> Task I64 ! mut) (-> Task I64 ! mut)))
(define (tries read)
  read)

(tries Task-tries)
