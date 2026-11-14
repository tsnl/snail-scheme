(import
 (only (snail core forms) host)
 (snail core base)
 (snail core io)
 (snail shell future))

(define (main) (→ Unit) (! host mut output-port completion)
  ;; Polling is immediate: a future is pending until its promise is fulfilled.
  (match (ann (make-promise) (Pair (Promise String) (Future String)))
    ((Pair promise future)
     (match (poll future)
       ((Pending) (write-line "pending"))
       ((Ready value) (write-line value)))
     (fulfill promise "taken")
     (match (poll future)
       ((Ready value) (write-line value))
       ((Pending) (write-line "still pending")))
     ;; A ready future stays ready.
     (match (poll future)
       ((Ready value) (write-line (string-append "again " value)))
       ((Pending) (write-line "still pending")))))
  ;; A promise that is never fulfilled leaves its future pending.
  (match (ann (make-promise) (Pair (Promise I64) (Future I64)))
    ((Pair promise future)
     (match (poll future)
       ((Ready value) (write-line (show value)))
       ((Pending) (write-line "never fulfilled")))))
  (unit))
