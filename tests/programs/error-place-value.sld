(import
 (snail core base))

;; A selector lambda still owns its linear argument. Observing a field
;; does not consume the rest of the record or release its work item.
(struct Task
  ((work (FnOnce → Unit))
   (tries I64)))

(define (tries (read (Fn Task → I64))) (→ (Fn Task → I64))
  read)

(tries (lambda (record) (● record tries)))
