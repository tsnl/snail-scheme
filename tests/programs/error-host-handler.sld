(import
 (snail core base))

(define main
  (lambda ()
    ;; No handler implements a builtin effect.
    (handle host ()
      (unit))
    (unit)))
