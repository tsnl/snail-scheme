(import
 (snail core base)
 (snail core io))

(typeclass (Bad A)
  (type (Output B))
  (: bad (-> A A)))
