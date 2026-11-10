(import
 (snail core base))
(struct Counter
  ((value (Ref I64))))
(instance (Drop (!) Counter)
  (define (drop counter) (match counter ((Counter _) (unit)))))
(let* ((counter (Counter (ref 0)))
       (advance (ann (lambda () (set! (ref-get (::value counter)) 1))
                     (impl (Fn -> Unit ! mut)))))
  (drop advance))
