;; Independently authored Wasm: a scalar provider and persistent GC references.
(module
  (type $node (struct (field i64) (field (ref null $node))))
  (import "example" "example_hide" (func $hide (param i64) (result i64)))
  (global $root (export "root") (mut (ref null $node)) (ref.null $node))
  (func (export "run") (param $value i64) (result i64)
    (global.set $root
      (struct.new $node
        (i64.add (call $hide (local.get $value)) (i64.const 2))
        (global.get $root)))
    (struct.get $node 0 (global.get $root)))
  (func (export "previous") (result i64)
    (struct.get $node 0 (struct.get $node 1 (global.get $root))))
  ;; Only this local retains the object while the scalar provider collects.
  ;; Neither function allocates: the import effect must reach its callers.
  (func $collect (drop (call $hide (i64.const 0))))
  (func (export "take-root") (result i64) (local $keep (ref null $node))
    (local.set $keep (global.get $root))
    (global.set $root (ref.null $node))
    (call $collect)
    (struct.get $node 0 (local.get $keep)))
  (func (export "trap") unreachable))
