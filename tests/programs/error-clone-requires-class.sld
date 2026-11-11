(import
 (snail core base))

;; A clone finds what it runs from its type alone, so an instance requires
;; nothing but the clones of its variables.
(struct (Box A)
  ((item A)))

(instance (Clone (! e) (Box A))
  (⊨ (Drop e A))
  (define clone
    (lambda (box) (match box
                    ((Box item) (Pair (Box item) (Box item)))))))
