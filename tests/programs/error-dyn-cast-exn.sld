(import
 (snail core base))
(effect exn ((ctl raise (dyn (Fn String -> Never)))))
(: integer (impl (Fn Any -> I64 ! exn)))
(define (integer value) value)
