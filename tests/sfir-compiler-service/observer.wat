(module
  (import "host" "character" (func $character (param i32)))
  (import "host" "message" (func $message))
  (import "host" "fail" (func $fail))
  (export "character" (func $character))
  (export "message" (func $message))
  (export "fail" (func $fail)))
