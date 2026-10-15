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
    (global.get $ready557)
   )
   (then
    (unreachable)
   )
  )
  (return_call $function179
   (struct.get $type33 1
    (global.get $global557)
   )
   (local.get $0)
  )
 )
