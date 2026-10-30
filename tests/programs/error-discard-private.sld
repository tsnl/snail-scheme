(import
 (snail core base)
 (snail core io)
 (only (snail core primitive) discard))

;; `discard` is what a drop becomes when releasing a value runs nothing,
;; so the primitive library keeps it: called on a handle, it would lose
;; the handle without releasing it.
(struct Handle
  ((name String)))

(instance (Drop (! console) Handle)
  (define (drop handle)
    (match handle
      ((Handle name) (write-line (string-append "released " name))))))

(discard (Handle "h"))
