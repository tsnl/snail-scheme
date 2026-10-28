(import
 (snail-core base))

;; A control operation's implementation runs where its handler is, after
;; the body has unwound to it, so its type cannot name effects to perform
;; where it was performed.
(effect Abort
  ((ctl abort (-> I64 I64))))

(effect Gen
  ((ctl yield (-> I64 Unit ! Abort))))

(unit)
