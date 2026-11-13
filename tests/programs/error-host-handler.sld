(import
 (snail core base)
 (only (snail core forms) host))

(define main
  (lambda ()
    ;; No handler implements a builtin effect.
    (handle host ()
      (unit))
    (unit)))
