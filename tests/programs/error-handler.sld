(import
 (snail core base))

(effect Store
  ((load (Fn → I64))
   (save (Fn I64 → Unit))))

(define main
  (lambda ()
    (handle Store
        ((load (lambda () 0)))
      (load))
    (unit)))
