(import
 (snail core base))

;; The host cannot be handed the rest of a computation, so a control
;; operation has no host default.
(effect Gen
  ((ctl next (-> I64 Unit)))
  (host "snail.library"
        ((next "snail:test/next"))))

(unit)
