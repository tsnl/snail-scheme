(import
 (snail core base)
 (snail core io))

(typeclass (Bad A)
  (type Output)
  (: bad (Fn A → A ! Output)))
