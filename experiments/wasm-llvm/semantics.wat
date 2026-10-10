(module
  (type $a (struct (field i32)))
  (type $b (struct (field i32)))
  (type $cell (struct (field (mut i32))))
  (import "env" "observe" (func $observe (param eqref)))

  ;; Equivalent structural types must share the decoder's canonical type.
  (func (export "equivalent") (result i32)
    (local $value eqref)
    (local.set $value (struct.new $a (i32.const 71)))
    (i32.add (ref.test (ref $b) (local.get $value))
      (struct.get $b 0 (ref.cast (ref $b) (local.get $value)))))

  (func (export "i31_signed_min") (result i32)
    (i31.get_s (ref.i31 (i32.const 1073741824))))
  (func (export "i31_unsigned_max") (result i32)
    (i31.get_u (ref.i31 (i32.const -1))))

  ;; Store operands are evaluated before checking the target for null.
  (func $rhs (result i32)
    (call $observe (ref.i31 (i32.const 37)))
    (i32.const 9))
  (func (export "store_order")
    (struct.set $cell 0 (ref.null $cell) (call $rhs)))
)
