(import
 (snail core base)
 (snail shell future))

(match (ann (make-promise) (Pair (Promise I64) (Future I64)))
  ((Pair promise future)
   (drop promise)
   (drop (poll future))
   (drop (poll future))))
