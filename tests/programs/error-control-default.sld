(import
 (snail core base))

;; No handler is in scope where a default runs, to be handed the rest of
;; the computation, so a control operation has no default.
(effect Gen
  ((ctl next (Fn I64 → Unit)))
  (default ((next (lambda (n) (unit))))))

(define main
  (lambda ()
    (unit)
    (unit)))
