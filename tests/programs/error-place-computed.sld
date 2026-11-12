(import
 (snail core base))

(struct Circle
  ((radius I64)))

(define main
  (lambda ()
    ;; No stored x slot exists to write.
    (let ((cell (ref (Circle 1))))
      (set! (● cell x) 4))
    (unit)))
