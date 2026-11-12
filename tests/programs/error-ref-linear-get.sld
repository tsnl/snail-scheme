(import
 (snail core base))

(define main
  (lambda ()
    (let ((cell (ref (once (lambda () (unit))))))
      (call-once (ref-get cell)))
    (unit)))
