(import
 (snail core base))
(effect exn ((ctl raise (Fn String → Never))))
(define (integer (value Any)) (→ I64) (! exn) value)
