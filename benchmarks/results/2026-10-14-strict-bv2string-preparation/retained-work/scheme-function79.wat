(func $function79 (type $call55) (param $0 (ref $type14)) (result (ref $type28))
  (local $1 i64)
  (local $2 i64)
  (local $3 (ref $type28))
  (if
   (i32.eqz
    (global.get $ready217)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global217)
   )
  )
  (if
   (i32.eqz
    (global.get $ready135)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global135)
   )
  )
  (if
   (i64.gt_s
    (local.tee $1
     (i64.extend_i32_u
      (struct.get $type14 1
       (local.get $0)
      )
     )
    )
    (local.get $1)
   )
   (then
    (unreachable)
   )
  )
  (if
   (i32.eqz
    (global.get $ready222)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global222)
   )
  )
  (local.set $2
   (call $function74
    (local.get $0)
    (local.get $1)
    (i32.const 0)
    (i32.const 1)
    (i64.const 0)
    (i64.const 0)
   )
  )
  (if
   (i32.eqz
    (global.get $ready109)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global109)
   )
  )
  (if
   (i64.gt_u
    (local.get $2)
    (i64.const 4294967295)
   )
   (then
    (unreachable)
   )
  )
  (if
   (i32.eqz
    (global.get $ready231)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global231)
   )
  )
  (drop
   (call $function77
    (local.tee $3
     (struct.new $type28
      (array.new_default $type29
       (i32.wrap_i64
        (local.get $2)
       )
      )
     )
    )
    (local.get $0)
    (local.get $1)
    (i32.const 0)
    (i32.const 1)
    (i64.const 0)
    (i64.const 0)
   )
  )
  (local.get $3)
 )
