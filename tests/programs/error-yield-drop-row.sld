(import
 (snail core base))

;; A handle live across a call that may yield is held by the frame, and a
;; dropped resumption would drop it, performing `audit`, which this
;; function's row does not allow.
(effect audit
  ((note (Fn String → Unit))))

(effect Ask
  ((ctl ask (Fn → I64))))

(struct Handle
  ((name String)))

(instance (Drop (! audit) Handle)
  (define drop
    (lambda (handle) (match handle
                       ((Handle name) (note name))))))

(define (keep) (→ Handle) (! Ask)
  (let ((handle (Handle "h")))
    (let ((answer (ask)))
      handle)))
