(import
 (snail-core base))

(effect Store
  ((load (-> I64))
   (save (-> I64 Unit))))

(handle Store
    ((load (lambda () 0)))
  (load))
