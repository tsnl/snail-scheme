(func $function203 (type $10) (param $0 (ref $type58)) (param $1 i32) (param $2 i32) (param $3 (ref $type138)) (param $4 (ref $type13)) (param $5 i64) (result (ref $type13))
  (local $6 i32)
  (local $7 (ref $type138))
  (drop
   (ref.as_non_null
    (global.get $global451)
   )
  )
  (if (result (ref $type13))
   (if (result i32)
    (local.tee $6
     (struct.get $type138 0
      (local.get $3)
     )
    )
    (then
     (if
      (i32.eq
       (local.get $6)
       (i32.const 1)
      )
      (then
       (drop
        (ref.cast (ref $type140)
         (local.get $3)
        )
       )
      )
      (else
       (drop
        (ref.cast (ref $type141)
         (local.get $3)
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
    (local.get $4)
   )
   (else
    (drop
     (ref.as_non_null
      (global.get $global717)
     )
    )
    (local.set $7
     (call $function198
      (local.get $0)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global456)
     )
    )
    (local.set $4
     (call $function135
      (local.get $3)
     )
    )
    (if
     (i32.eqz
      (local.get $2)
     )
     (then
      (unreachable)
     )
    )
    (return_call $function203
     (local.get $0)
     (local.get $1)
     (local.get $2)
     (local.get $7)
     (local.get $4)
     (i64.add
      (local.get $5)
      (i64.const 1)
     )
    )
   )
  )
 )
