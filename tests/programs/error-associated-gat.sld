(import
 (snail core base)
 (snail core io))

(typeclass (Bad A)
  (type (Output B))
  (: bad (impl (Fn A -> A))))
