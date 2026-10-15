(func $function183 (type $47) (param $0 i64) (param $1 (ref $type18)) (param $2 i32) (param $3 i32) (param $4 i64) (result i32)
  (local $5 i32)
  (local $6 i64)
  (if (result i32)
   (i64.gt_s
    (local.tee $6
     (i64.extend_i32_u
      (struct.get $type18 1
       (local.get $1)
      )
     )
    )
    (local.get $4)
   )
   (then
    (if
     (i64.ge_u
      (local.get $4)
      (local.get $6)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global527)
     )
    )
    (if (result i32)
     (local.tee $5
      (i64.eq
       (i64.extend_i32_u
        (array.get $type19
         (if (result (ref $type19))
          (i32.lt_u
           (local.tee $5
            (i32.wrap_i64
             (local.get $4)
            )
           )
           (i32.const 8192)
          )
          (then
           (struct.get $type18 2
            (local.get $1)
           )
          )
          (else
           (ref.as_non_null
            (array.get $type20
             (struct.get $type18 3
              (local.get $1)
             )
             (i32.sub
              (i32.shr_u
               (local.get $5)
               (i32.const 13)
              )
              (i32.const 1)
             )
            )
           )
          )
         )
         (i32.and
          (local.get $5)
          (i32.const 8191)
         )
        )
       )
       (local.get $0)
      )
     )
     (then
      (local.get $5)
     )
     (else
      (if
       (i32.eqz
        (local.get $3)
       )
       (then
        (unreachable)
       )
      )
      (return_call $function183
       (local.get $0)
       (local.get $1)
       (local.get $2)
       (local.get $3)
       (i64.add
        (local.get $4)
        (i64.const 1)
       )
      )
     )
    )
   )
   (else
    (i32.const 0)
   )
  )
 )
