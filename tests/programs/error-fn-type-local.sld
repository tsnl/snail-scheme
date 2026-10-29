(import
 (snail core base))

;; A local bound to a function is a closure, whatever it holds.
(: run (-> (Fn I64 I64) I64))
(define (run f)
  (f 1))

(: indirect (-> I64))
(define (indirect)
  (let ((g (fn (x) (* x 3))))
    (run g)))
