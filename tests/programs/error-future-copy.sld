(import
 (snail core base)
 (snail shell future))

(define main
  (lambda ()
    (match (ann (make-promise) (Pair (Promise I64) (Future I64)))
      ((Pair promise future)
       (drop promise)
       (drop (poll future))
       (drop (poll future))))
    (unit)))
