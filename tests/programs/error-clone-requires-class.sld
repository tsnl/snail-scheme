(import
 (snail core base))

;; A clone finds what it runs from its type alone, so an instance requires
;; nothing but the clones of its variables.
(struct (Box A)
  ((item A)))

(instance (Clone (! e) (Box A))
  (requires (Drop e A))
  (define (clone box)
    (match box
      ((Box item) (Pair (Box item) (Box item))))))
