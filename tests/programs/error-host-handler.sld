(import
 (snail core base)
 (only (snail core forms) Host))

(define main
  (lambda ()
    ;; No handler implements a builtin effect.
    (handle Host ()
      (unit))
    (unit)))
