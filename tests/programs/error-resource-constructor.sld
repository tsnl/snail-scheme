;; Only `link-bytes` makes a Resource: the type is exported without its
;; constructor, so holding one is evidence that its file ships.
(import
 (snail core base)
 (snail shell resource))

(define forged (Resource 0))
