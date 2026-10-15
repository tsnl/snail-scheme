(func $export0 (param $0 i64) (result i64)
  (if
   (i32.ne
    (global.get $execution)
    (i32.const 2)
   )
   (then
    (unreachable)
   )
  )
  (if
   (i32.eqz
    (global.get $ready762)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global762)
   )
  )
  (return_call $function210
   (local.get $0)
   (i32.const 0)
   (i32.const 1)
   (i64.const 0)
   (struct.new $type15
    (i32.const 1)
   )
  )
 )
