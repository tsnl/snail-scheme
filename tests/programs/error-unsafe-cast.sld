(import
 (snail core base)
 (snail shell wasm))

(define (count (function Funcref)) (→ I64)
  (unsafe-cast function))
(expose count "count")
