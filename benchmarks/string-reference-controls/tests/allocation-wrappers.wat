 (func $control_malloc (param $size i32) (result i32)
  (global.set $control_allocation_calls
   (i64.add (global.get $control_allocation_calls) (i64.const 1)))
  (global.set $control_requested_bytes
   (i64.add (global.get $control_requested_bytes) (i64.extend_i32_u (local.get $size))))
  (call $malloc (local.get $size)))
 (func $control_calloc (param $size i32) (param $count i32) (result i32)
  (local $pointer i32)
  (global.set $control_allocation_calls
   (i64.add (global.get $control_allocation_calls) (i64.const 1)))
  (global.set $control_requested_bytes
   (i64.add (global.get $control_requested_bytes)
    (i64.mul (i64.extend_i32_u (local.get $size)) (i64.extend_i32_u (local.get $count)))))
  (global.set $in_control_allocation (i32.const 1))
  (local.set $pointer (call $calloc (local.get $size) (local.get $count)))
  (global.set $in_control_allocation (i32.const 0))
  (local.get $pointer))
