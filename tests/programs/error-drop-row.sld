(import
 (snail core base)
 (owned handle))

;; Dropping a handle performs `log`, which this signature does not allow.
(: release (impl (Fn Handle -> Unit)))
(define (release handle)
  (drop handle))
