(import
 (snail core base)
 (snail core io)
 (snail shell wasm))

(: count (-> Funcref I64))
(define (count function)
  (unsafe-cast function))

(match (load-module "counter" "counter.wasm")
  ((Ok module)
   (match (module-export module "count")
     ((Ok function) (display (count function)))
     ((Err _) (unit))))
  ((Err _) (unit)))
