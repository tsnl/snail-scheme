(import
 (snail core base)
 (snail core io))

;; type-test compares the same TypeId, so it cannot tell a function that
;; logs from a total one either, and asking would answer wrongly.
(effect Log
  ((log (-> String Unit))))

(: boxed Any)
(define boxed (type-convert (lambda () (unit)) Any))

(display (type-test boxed (-> Unit ! Log)))
