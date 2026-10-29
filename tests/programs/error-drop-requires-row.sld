(import
 (snail core base))

;; A head's row ends with a variable only as the row of the instance's
;; requirements (Drop e A); this instance has none, so its row is closed.
(struct Handle
  ((id I64)))

(instance (Drop (! e) Handle)
  (define (drop handle)
    (match handle
      ((Handle _) (unit)))))
