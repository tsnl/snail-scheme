(import
 (snail core base))
(effect exn ((ctl raise (dyn (Fn String → Never)))))
(define (integer (value Any)) (→ I64) (! exn) value)
