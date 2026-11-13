(import
 (snail core base))

(effect Choose ((ctl choose (Fn → I64))))
(define (memo) (→ (Fn → I64 ! Choose)) (cache (lambda () (choose))))
(define (main) (→ Unit)
  (handle Choose ((choose (lambda (resume) (resume 1)))) ((memo)))
  (unit))
