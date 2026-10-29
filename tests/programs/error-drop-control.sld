(import
 (snail core base))

;; A drop runs to completion, so it cannot yield.
(effect Gen
  ((ctl next (-> Unit))))

(struct Handle
  ((id I64)))

(instance (Drop (! Gen) Handle)
  (define (drop handle)
    (match handle
      ((Handle _) (next)))))
