(import
 (snail core base))

;; An instance's row is written in its head: closed, or ending with the row
;; of its requirements (Drop e A), which this instance does not have.
(struct Handle
  ((id I64)))

(instance (Drop e Handle)
  (define (drop handle)
    (match handle
      ((Handle _) (unit)))))
