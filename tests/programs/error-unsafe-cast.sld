(import
 (snail-core base)
 (snail-core io)
 (snail-core wasm))

(: count (-> Module I64 ! wasm))
(define (count module)
  (unsafe-cast (module-export module "count")))

(display (count (load-module "counter" "counter.wasm")))
