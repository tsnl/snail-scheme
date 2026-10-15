(func $function99 (type $2) (param $0 i64) (param $1 i64) (param $2 (ref $type42)) (param $3 i32) (param $4 i32) (param $5 i32) (param $6 i32) (param $7 i32) (param $8 i32) (param $9 i32) (param $10 i64) (result i32)
  (local $11 i64)
  (local $12 i32)
  (local $13 (ref $type28))
  (local $14 (ref $type28))
  (local $15 (ref $type14))
  (local $16 (ref $type14))
  (local $scratch i32)
  (if (result i32)
   (i64.eq
    (local.get $0)
    (local.get $10)
   )
   (then
    (i32.const 0)
   )
   (else
    (if
     (i32.eqz
      (local.get $5)
     )
     (then
      (unreachable)
     )
    )
    (if
     (i32.eqz
      (local.get $3)
     )
     (then
      (unreachable)
     )
    )
    (local.set $11
     (call_ref $call42
      (struct.get $type42 1
       (local.get $2)
      )
      (local.get $1)
      (struct.get $type42 0
       (local.get $2)
      )
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
      (local.get $11)
      (i64.const 4294967295)
     )
     (then
      (unreachable)
     )
    )
    (local.set $13
     (call $function93
      (local.get $2)
      (local.get $3)
      (local.get $11)
      (struct.new $type28
       (array.new_default $type29
        (i32.wrap_i64
         (local.get $11)
        )
       )
      )
      (i32.const 0)
      (i32.const 1)
      (i64.const 0)
     )
    )
    (if
     (i32.eqz
      (global.get $ready207)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global207)
     )
    )
    (if
     (i32.eqz
      (global.get $ready244)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global244)
     )
    )
    (if
     (i32.eqz
      (local.get $7)
     )
     (then
      (unreachable)
     )
    )
    (if
     (i32.eqz
      (global.get $ready164)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global164)
     )
    )
    (local.set $14
     (call $function79
      (local.tee $15
       (call $function57
        (local.get $13)
        (i64.extend_i32_u
         (array.len
          (struct.get $type28 0
           (local.get $13)
          )
         )
        )
       )
      )
     )
    )
    (if
     (i32.eqz
      (global.get $ready164)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global164)
     )
    )
    (local.set $16
     (call $function57
      (local.get $14)
      (i64.extend_i32_u
       (array.len
        (struct.get $type28 0
         (local.get $14)
        )
       )
      )
     )
    )
    (if
     (i32.eqz
      (global.get $ready103)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global103)
     )
    )
    (call $function86
     (block (result i32)
      (local.set $scratch
       (if (result i32)
        (i64.eq
         (i64.extend_i32_u
          (struct.get $type14 1
           (local.get $15)
          )
         )
         (i64.extend_i32_u
          (struct.get $type14 1
           (local.get $16)
          )
         )
        )
        (then
         (call $function40
          (local.get $15)
          (local.get $16)
          (i32.const 0)
          (i32.const 1)
          (i64.const 0)
         )
        )
        (else
         (i32.const 0)
        )
       )
      )
      (if
       (i32.eqz
        (global.get $ready262)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global262)
       )
      )
      (local.get $scratch)
     )
    )
    (if
     (i32.eqz
      (local.get $9)
     )
     (then
      (unreachable)
     )
    )
    (return_call $function99
     (local.get $0)
     (local.get $1)
     (local.get $2)
     (local.get $3)
     (local.get $4)
     (local.get $5)
     (local.get $6)
     (local.get $7)
     (local.get $8)
     (local.get $9)
     (i64.add
      (local.get $10)
      (i64.const 1)
     )
    )
   )
  )
 )
