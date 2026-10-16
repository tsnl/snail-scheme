;; Independently authored Wasm: a scalar provider and persistent GC references.
(module
  (type $node (struct (field i64) (field (ref null $node))))
  (import "example" "example_hide" (func $hide (param i64) (result i64)))
  (global $root (mut (ref null $node)) (ref.null $node))
  (func (export "run") (param $value i64) (result i64)
    (global.set $root
      (struct.new $node
        (i64.add (call $hide (local.get $value)) (i64.const 2))
        (global.get $root)))
    (struct.get $node 0 (global.get $root)))
  (func (export "previous") (result i64)
    (struct.get $node 0 (struct.get $node 1 (global.get $root))))
  (func (export "trap") unreachable))
