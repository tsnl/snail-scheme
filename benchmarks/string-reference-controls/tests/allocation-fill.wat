   (if (global.get $in_control_allocation)
    (then
     (global.set $control_zero_fill_calls
      (i64.add (global.get $control_zero_fill_calls) (i64.const 1)))
     (global.set $control_zero_fill_bytes
      (i64.add (global.get $control_zero_fill_bytes) (i64.extend_i32_u (local.get $2))))))
