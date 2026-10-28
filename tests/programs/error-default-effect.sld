(import
 (snail-core base)
 (snail-core io))

;; A default has its operation's type: it may perform only the effects
;; that type names, which its performer is charged.
(effect Clock
  ((now (-> I64)))
  (default
    ((now (lambda () (write-line "now") 0)))))

(now)
