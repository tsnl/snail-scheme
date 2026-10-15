(module
  (global $trace (export "trace") (mut i32) (i32.const 0))
  (func (export "mark") (param i32)
    (global.set $trace (i32.add (i32.mul (global.get $trace) (i32.const 10)) (local.get 0))))
  (func (export "bad-bool") (result i32) (i32.const 2))
  (func (export "bad-char") (result i32) (i32.const 55296)))
