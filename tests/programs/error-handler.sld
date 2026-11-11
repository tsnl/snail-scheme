(import
 (snail core base))

(effect Store
  ((load (dyn (Fn -> I64)))
   (save (dyn (Fn I64 -> Unit)))))

(handle Store
    ((load (lambda () 0)))
  (load))
