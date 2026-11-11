(import
 (snail core base))

;; No handler is in scope where a default runs, to be handed the rest of
;; the computation, so a control operation has no default.
(effect Gen
  ((ctl next (dyn (Fn I64 -> Unit))))
  (default ((next (lambda (n) (unit))))))

(unit)
