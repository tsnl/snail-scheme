(import
 (snail core base)
 (associated-policy))

(define main
  (lambda ()
    ;; Import binds the policy name, without activating its instances.
    (generic (ann 1 I64) (ann 2 I64))
    (unit)))
