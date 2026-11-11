(import
 (snail core base))
(struct Bad
  ((work (Array (dyn (FnOnce → Unit))))))
(unit)
