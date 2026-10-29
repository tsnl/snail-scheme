(import
 (snail core base)
 (only (snail core forms) host))

;; No handler implements a builtin effect.
(handle host ()
  (unit))
