(import
 (snail-core base)
 (snail-core wasm))

;; A plugin's function is looked up at a function type of data, as only
;; such a function can be exposed with `dynamic`.
(: twice (-> Plugin (Result (-> (-> I64 I64) I64 I64) LoadError) ! wasm))
(define (twice plugin)
  (plugin-function plugin "twice"))

(match (load-plugin "plugin/modules.json")
  ((Ok plugin) (twice plugin) (unit))
  ((Err _) (unit)))
