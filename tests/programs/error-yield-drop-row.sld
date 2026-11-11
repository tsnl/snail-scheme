(import
 (snail core base))

;; A handle live across a call that may yield is held by the frame, and a
;; dropped resumption would drop it, performing `audit`, which this
;; function's row does not allow.
(effect audit
  ((note (dyn (Fn String -> Unit)))))

(effect Ask
  ((ctl ask (dyn (Fn -> I64)))))

(struct Handle
  ((name String)))

(instance (Drop (! audit) Handle)
  (define (drop handle)
    (match handle
      ((Handle name) (note name)))))

(: keep (impl (Fn -> Handle ! Ask)))
(define (keep)
  (let ((handle (Handle "h")))
    (let ((answer (ask)))
      handle)))
