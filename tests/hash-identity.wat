;; Keep a cyclic object live exclusively through a Wasm global between JS jobs.
(module
  (import "snail.host" "hash-identity" (func $hash (param eqref) (result i32)))
  (type $node (struct (field (mut eqref))))
  (global $saved (mut eqref) (ref.null eq))
  (func (export "pin")
    (global.set $saved (struct.new $node (ref.null eq)))
    (struct.set $node 0 (ref.cast (ref $node) (global.get $saved)) (global.get $saved)))
  (func (export "hash") (result i32) (call $hash (global.get $saved)))
  (func (export "get") (result eqref) (global.get $saved))
  (func (export "drop") (global.set $saved (ref.null eq)))
  (func (export "immediate") (param i32) (result i32) (call $hash (ref.i31 (local.get 0)))))
