(import
 (snail core base))

;; A once lambda dropped unrun drops what it captured under its own row,
;; which here allows nothing, while the handle's drop performs `audit`.
(effect audit
  ((note (-> String Unit))))

(struct Handle
  ((name String)))

(instance (Drop (! audit) Handle)
  (define (drop handle)
    (match handle
      ((Handle name) (note name)))))

(: keep (-> (FnOnce Handle)))
(define (keep)
  (let ((handle (Handle "h")))
    (once (lambda () handle))))
