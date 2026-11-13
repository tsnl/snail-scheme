(import
 (snail core base))

;; A drop runs to completion, so it cannot yield.
(effect Gen
  ((ctl next (Fn → Unit))))

(struct Handle
  ((id I64)))

(instance (Drop (! Gen) Handle)
  (define (drop (handle Handle)) (→ Unit) (! Gen)
    (match handle
      ((Handle _) (next)))))
