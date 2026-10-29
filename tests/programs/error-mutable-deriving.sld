(import
 (snail core base))

;; A derived instance matches every field, which a struct with identity
;; cannot offer.
(struct Counter
  ((count mut I64))
  (deriving Serialize))
