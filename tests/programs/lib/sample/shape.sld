;; Derives wire instances without importing (snail shell wire): deriving
;; loads it.
(define-library (sample shape)
  (export
   Shape
   Square
   Rectangle
   shape-area)
  (import
   (snail core base))
  (begin

    (enum Shape
      (Square ((side I64)))
      (Rectangle ((width I64) (height I64)))
      (deriving Serialize Deserialize))

    (: shape-area (-> Shape I64))
    (define (shape-area shape)
      (match shape
        ((Square side) (* side side))
        ((Rectangle width height) (* width height))))))
