(import
 (snail core base)
 (snail core io)
 (snail shell wasm))

(define (count (function Funcref)) (→ I64)
  (unsafe-cast function))

(define main
  (lambda ()
    (match (load-module "counter" "counter.wasm")
      ((Ok module)
       (match (module-export module "count")
         ((Ok function) (display (count function)))
         ((Err _) (unit))))
      ((Err _) (unit)))
    (unit)))
