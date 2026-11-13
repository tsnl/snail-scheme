(import
 (snail core base))

;; Every Node would hold another Node, through a field, so no
;; program can build one. An empty type is an enum with no cases instead.
(struct Node
  ((next Node)))
