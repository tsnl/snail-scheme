(import
 (snail core base))
(struct Bad
  ((work (Ref (Once (-> Unit))))))
(unit)
