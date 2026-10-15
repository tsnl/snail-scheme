(func $function57 (type $23) (param $0 (ref $type28)) (param $1 i64) (result (ref $type14))
  (local $2 i32)
  (local $3 i32)
  (local $4 i32)
  (local $5 i32)
  (local $6 i32)
  (local $7 i64)
  (local $8 (ref null $type16))
  (local $9 (ref $type14))
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
  (local.set $7
   (i64.extend_i32_u
    (array.len
     (struct.get $type28 0
      (local.get $0)
     )
    )
   )
  )
  (if
   (if (result i32)
    (local.tee $2
     (i64.lt_s
      (local.get $1)
      (i64.const 0)
     )
    )
    (then
     (local.get $2)
    )
    (else
     (i64.gt_s
      (local.get $1)
      (local.get $7)
     )
    )
   )
   (then
    (unreachable)
   )
  )
  (if
   (i32.eqz
    (global.get $ready169)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global169)
   )
  )
  (local.set $7
   (call $function59
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
    (global.get $ready61)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global61)
   )
  )
  (if
   (i64.gt_u
    (local.get $7)
    (i64.const 4294967294)
   )
   (then
    (unreachable)
   )
  )
  (if
   (local.tee $3
    (i32.sub
     (local.tee $2
      (i32.wrap_i64
       (local.get $7)
      )
     )
     (local.tee $5
      (select
       (i32.const 8192)
       (local.get $2)
       (i32.ge_u
        (local.get $2)
        (i32.const 8192)
       )
      )
     )
    )
   )
   (then
    (local.set $8
     (array.new_default $type16
      (i32.shr_u
       (i32.sub
        (local.get $2)
        (i32.const 1)
       )
       (i32.const 13)
      )
     )
    )
    (loop $label
     (array.set $type16
      (local.get $8)
      (local.get $4)
      (array.new_default $type15
       (local.tee $6
        (select
         (i32.const 8192)
         (local.get $3)
         (i32.ge_u
          (local.get $3)
          (i32.const 8192)
         )
        )
       )
      )
     )
     (local.set $4
      (i32.add
       (local.get $4)
       (i32.const 1)
      )
     )
     (br_if $label
      (local.tee $3
       (i32.sub
        (local.get $3)
        (local.get $6)
       )
      )
     )
    )
   )
  )
  (if
   (i32.eqz
    (global.get $ready195)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global195)
   )
  )
  (drop
   (call $function67
    (local.tee $9
     (struct.new $type14
      (i32.const 1)
      (local.get $2)
      (array.new_default $type15
       (local.get $5)
      )
      (local.get $8)
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
  (local.get $9)
 )
