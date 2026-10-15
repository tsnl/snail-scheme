 ;; Separate counters: selected trial allocations include seeds, not startup.
 (global $in_control_allocation (mut i32) (i32.const 0))
 (global $control_allocation_calls (export "control_allocation_calls") (mut i64) (i64.const 0))
 (global $control_requested_bytes (export "control_requested_bytes") (mut i64) (i64.const 0))
 (global $control_zero_fill_calls (export "control_zero_fill_calls") (mut i64) (i64.const 0))
 (global $control_zero_fill_bytes (export "control_zero_fill_bytes") (mut i64) (i64.const 0))
