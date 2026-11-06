;; A second library that derives without importing (snail shell wire),
;; whose instances use those (sample shape) derives.
(define-library (sample route)
  (export
   Stop
   Route)
  (import
   (snail core base)
   (sample shape))
  (begin

    (struct (Stop T)
      ((label T)
       (shape Shape))
      (deriving Serialize Deserialize))

    (struct Route
      ((stops (List (Stop String)))
       (length I64))
      (deriving Serialize Deserialize))))
