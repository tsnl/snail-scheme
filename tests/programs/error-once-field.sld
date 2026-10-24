(import
 (lofi base))
(struct Bad
  ((work (Ref (Once (-> Unit))))))
(unit)
