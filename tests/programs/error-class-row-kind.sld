(import
 (snail core base))

;; A class parameter is a row when a method performs it, and a type when a
;; method writes it as one; it cannot be both.
(typeclass (Mixed e)
  (: mixed (impl (Fn e → Unit ! e))))
