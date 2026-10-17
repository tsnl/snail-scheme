(module
  (import "host" "call" (func $call (result i32)))
  (func (export "callback") (result i32) (call $call)))
