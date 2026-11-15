(import
 (snail core base))

;; An operation that answers Never is never resumed, so its implementation
;; takes the operation's arguments alone.
(effect Fail
  ((ctl fail (Fn String → Never))))

(define main
  (lambda ()
    (handle Fail ((fail (lambda (message resume) 0)))
      (absurd (fail "no")))
    (unit)))
