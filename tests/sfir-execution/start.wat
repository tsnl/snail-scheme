(module
  (import "probe" "mark" (func $mark (param i32)))
  (func $start (call $mark (i32.const 9)))
  (start $start))
