(import
 (snail core base))

;; An operation that answers Never is never resumed, so its implementation
;; takes the operation's arguments alone.
(effect Fail
  ((ctl fail (-> String Never))))

(handle Fail ((fail (lambda (message resume) 0)))
  (absurd (fail "no")))
