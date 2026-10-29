(import
 (snail core base))

;; A struct with a mutable field has no pure replacements: a copy would be
;; a second object with an identity of its own.
(struct Counter
  ((name String)
   (count mut I64)))

(Counter-name-set (Counter "clicks" 0) "taps")
