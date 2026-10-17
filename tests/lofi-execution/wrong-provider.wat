(module
  (global $trace (export "trace") (mut i32) (i32.const 0))
  (func (export "mark") (param i64)
    (global.set $trace (i32.const 9))))
