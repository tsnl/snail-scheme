(import
 (snail core base)
 (snail shell wasm))

;; A plugin's function is looked up at a function type of data, as only
;; such a function can be exposed with `dynamic`.
(define (twice (plugin Plugin))
  (→ (Result (Fn (Fn I64 → I64) I64 → I64) LoadError))
  (! wasm)
  (plugin-function plugin "twice"))

(match (load-plugin "plugin/modules.json")
  ((Ok plugin) (twice plugin) (unit))
  ((Err _) (unit)))
