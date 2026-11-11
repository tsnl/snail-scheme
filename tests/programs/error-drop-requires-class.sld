(import
 (snail core base))

;; A drop finds what it runs from its type alone, so an instance requires
;; nothing but the drops of its variables.
(struct (Box A)
  ((item A)))

(instance (Drop (!) (Box A))
  (⊨ (Show (!) A))
  (define drop
    (lambda (box) (match box
                    ((Box item) (drop item))))))
