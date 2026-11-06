(import
 (snail core base)
 (snail shell future))

(match (ann (make-promise) (Pair (Promise I64) (Future I64)))
  ((Pair promise future)
   (drop (fulfill promise 1))
   (drop (fulfill promise 2))
   (drop future)))
