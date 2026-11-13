(import
 (only (snail core forms) host)
 (snail core base)
 (snail core io)
 (snail shell future))

(record Resource
  ((name String)))

(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource
      ((Resource name) (write-line (string-append "released " name))))))

(define (main) (→ Unit) (! host mut output-port completion)
  ;; Polling is immediate, and a pending poll keeps the receiver linear.
  (match (ann (make-promise) (Pair (Promise Resource) (Future Resource)))
    ((Pair promise future)
     (match (poll future)
       ((Pending future)
        (write-line "pending")
        (match (fulfill promise (new Resource (name "taken")))
          ((Ok _) (unit))
          ((Err resource) (drop resource)))
        (match (poll future)
          ((Ready (Completed resource)) (drop resource))
          ((Ready (Abandoned)) (write-line "unexpected abandonment"))
          ((Pending future) (drop future))))
       ((Ready result) (drop promise) (drop result)))))
  ;; A canceled receiver returns an unsent resource to the sender.
  (match (ann (make-promise) (Pair (Promise Resource) (Future Resource)))
    ((Pair promise future)
     (drop future)
     (match (fulfill promise (new Resource (name "unsent")))
       ((Ok _) (unit))
       ((Err resource) (drop resource)))))
  ;; A fulfilled but unpolled result is still released exactly once.
  (match (ann (make-promise) (Pair (Promise Resource) (Future Resource)))
    ((Pair promise future)
     (match (fulfill promise (new Resource (name "buffered")))
       ((Ok _) (unit))
       ((Err resource) (drop resource)))
     (drop future)))
  ;; Dropping the producer makes a terminal, inspectable completion.
  (match (ann (make-promise) (Pair (Promise I64) (Future I64)))
    ((Pair promise future)
     (drop promise)
     (match (poll future)
       ((Ready (Abandoned)) (write-line "abandoned"))
       ((Ready (Completed value)) (write-line (show value)))
       ((Pending future) (drop future)))))
  (unit))
