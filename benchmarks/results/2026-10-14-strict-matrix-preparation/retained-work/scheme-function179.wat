(func $function179 (type $call33) (param $0 structref) (param $1 i64) (result i64)
  (local $2 i64)
  (local $3 i64)
  (if (result i64)
   (i64.le_s
    (local.get $1)
    (i64.const 0)
   )
   (then
    (if
     (i32.eqz
      (global.get $ready546)
     )
     (then
      (unreachable)
     )
    )
    (i64.extend_i32_u
     (i32.ne
      (global.get $global546)
      (i32.const 0)
     )
    )
   )
   (else
    (if
     (i32.eqz
      (global.get $ready544)
     )
     (then
      (unreachable)
     )
    )
    (if
     (i32.eqz
      (global.get $ready559)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (struct.get $type60 1
      (global.get $global559)
     )
    )
    (local.set $2
     (call $foreign2
      (global.get $global544)
     )
    )
    (if
     (i32.eqz
      (global.get $ready545)
     )
     (then
      (unreachable)
     )
    )
    (if
     (i32.eqz
      (global.get $ready559)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (struct.get $type60 1
      (global.get $global559)
     )
    )
    (local.set $3
     (call $foreign2
      (global.get $global545)
     )
    )
    (if
     (i32.eqz
      (global.get $ready472)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global472)
     )
    )
    (return_call $function181
     (local.get $1)
     (i32.const 0)
     (i32.const 1)
     (i64.const 1)
     (call $function156
      (local.get $2)
      (local.get $3)
     )
    )
   )
  )
 )
