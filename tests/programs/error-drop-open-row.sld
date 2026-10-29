(import
 (snail core base))

;; An instance's row is written in its head and closed.
(struct Handle
  ((id I64)))

(instance (Drop e Handle)
  (define (drop handle)
    (match handle
      ((Handle _) (unit)))))
