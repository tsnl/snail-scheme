(module
  (global $count (mut i32) (i32.const 0))
  (func (export "tick") (result i32)
    (global.set $count (i32.add (global.get $count) (i32.const 1)))
    (global.get $count))
  (func (export "count") (result i32) (global.get $count)))
