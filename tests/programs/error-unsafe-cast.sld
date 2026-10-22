(import
 (lofi base)
 (lofi io)
 (lofi wasm))

(: count (-> Module I64 ! wasm))
(define (count module)
  (unsafe-cast (module-export module "count")))

(display (count (load-module "counter" "counter.wasm")))
