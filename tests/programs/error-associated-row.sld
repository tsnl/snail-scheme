(import
 (snail core base)
 (snail core io))

(typeclass (Bad A)
  (type Output)
  (: bad (impl (Fn A → A ! Output))))
