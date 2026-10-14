(func $function201 (type $call198) (param $0 (ref $type58)) (param $1 f64) (result f64)
  (local $2 (ref $type138))
  (local $3 (ref $type13))
  (local $4 i32)
  (local $5 f64)
  (local $scratch (ref $type13))
  (drop
   (ref.as_non_null
    (global.get $global717)
   )
  )
  (local.set $2
   (call $function198
    (local.get $0)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global451)
   )
  )
  (if (result f64)
   (if (result i32)
    (local.tee $4
     (struct.get $type138 0
      (local.get $2)
     )
    )
    (then
     (if
      (i32.eq
       (local.get $4)
       (i32.const 1)
      )
      (then
       (drop
        (ref.cast (ref $type140)
         (local.get $2)
        )
       )
      )
      (else
       (drop
        (ref.cast (ref $type141)
         (local.get $2)
        )
       )
      )
     )
     (i32.const 0)
    )
    (else
     (i32.const 1)
    )
   )
   (then
    (local.get $1)
   )
   (else
    (drop
     (ref.as_non_null
      (global.get $global456)
     )
    )
    (local.set $5
     (call $function199
      (block (result (ref $type13))
       (local.set $scratch
        (call $function135
         (local.get $2)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global723)
        )
       )
       (local.get $scratch)
      )
     )
    )
    (if
     (i32.eqz
      (global.get $ready732)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global732)
     )
    )
    (return_call $function201
     (local.get $0)
     (f64.add
      (local.get $5)
      (local.get $1)
     )
    )
   )
  )
 )
