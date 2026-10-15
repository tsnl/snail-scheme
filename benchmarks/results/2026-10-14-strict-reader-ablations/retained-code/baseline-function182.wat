(func $function182 (type $call150) (param $0 i64) (result i32)
  (local $1 i32)
  (if (result i32)
   (local.tee $1
    (i64.lt_s
     (local.get $0)
     (i64.const 0)
    )
   )
   (then
    (local.get $1)
   )
   (else
    (drop
     (ref.as_non_null
      (global.get $global525)
     )
    )
    (if (result i32)
     (local.tee $1
      (if (result i32)
       (i64.ge_s
        (local.get $0)
        (i64.const 0)
       )
       (then
        (if
         (i64.gt_u
          (local.get $0)
          (i64.const 1114111)
         )
         (then
          (unreachable)
         )
        )
        (if
         (i32.and
          (i64.le_u
           (local.get $0)
           (i64.const 57343)
          )
          (i64.ge_u
           (local.get $0)
           (i64.const 55296)
          )
         )
         (then
          (unreachable)
         )
        )
        (i32.eq
         (call $snail:datum/whitespace
          (i32.wrap_i64
           (local.get $0)
          )
         )
         (i32.const 1)
        )
       )
       (else
        (i32.const 0)
       )
      )
     )
     (then
      (local.get $1)
     )
     (else
      (return_call $function183
       (local.get $0)
       (global.get $string21)
       (i32.const 0)
       (i32.const 1)
       (i64.const 0)
      )
     )
    )
   )
  )
 )
