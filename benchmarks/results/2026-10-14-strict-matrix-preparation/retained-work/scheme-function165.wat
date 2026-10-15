(func $function165 (type $17) (param $0 i64) (param $1 (ref $type84)) (param $2 (ref null $type32)) (result (ref null $type32))
  (if
   (i32.eqz
    (global.get $ready368)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (struct.get $type61 1
    (global.get $global368)
   )
  )
  (if
   (i64.eqz
    (local.get $0)
   )
   (then
    (return_call_ref $call84
     (struct.get $type84 1
      (local.get $1)
     )
     (ref.null none)
     (local.get $2)
     (struct.get $type84 0
      (local.get $1)
     )
    )
   )
   (else
    (if
     (i32.eqz
      (global.get $ready509)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global509)
     )
    )
    (local.set $2
     (call $function165
      (i64.sub
       (local.get $0)
       (i64.const 1)
      )
      (struct.new $type84
       (ref.func $function167)
       (struct.new $environment167
        (local.get $1)
       )
      )
      (local.get $2)
     )
    )
    (if
     (i32.eqz
      (global.get $ready509)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global509)
     )
    )
    (return_call $function165
     (i64.sub
      (local.get $0)
      (i64.const 1)
     )
     (struct.new $type84
      (ref.func $function166)
      (struct.new $environment166
       (local.get $1)
      )
     )
     (local.get $2)
    )
   )
  )
  (unreachable)
 )
