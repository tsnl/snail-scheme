(func $function40 (type $24) (param $0 (ref $type14)) (param $1 (ref $type14)) (param $2 i32) (param $3 i32) (param $4 i64) (result i32)
  (local $5 i32)
  (local $6 i32)
  (if (result i32)
   (local.tee $5
    (i64.eq
     (i64.extend_i32_u
      (struct.get $type14 1
       (local.get $0)
      )
     )
     (local.get $4)
    )
   )
   (then
    (local.get $5)
   )
   (else
    (if
     (i64.ge_u
      (local.get $4)
      (i64.extend_i32_u
       (struct.get $type14 1
        (local.get $0)
       )
      )
     )
     (then
      (unreachable)
     )
    )
    (if (result i32)
     (i32.eq
      (array.get $type15
       (if (result (ref $type15))
        (i32.lt_u
         (local.tee $5
          (i32.wrap_i64
           (local.get $4)
          )
         )
         (i32.const 8192)
        )
        (then
         (struct.get $type14 2
          (local.get $0)
         )
        )
        (else
         (ref.as_non_null
          (array.get $type16
           (struct.get $type14 3
            (local.get $0)
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
      (block (result i32)
       (if
        (i64.ge_u
         (local.get $4)
         (i64.extend_i32_u
          (struct.get $type14 1
           (local.get $1)
          )
         )
        )
        (then
         (unreachable)
        )
       )
       (array.get $type15
        (if (result (ref $type15))
         (i32.lt_u
          (local.tee $5
           (i32.wrap_i64
            (local.get $4)
           )
          )
          (i32.const 8192)
         )
         (then
          (struct.get $type14 2
           (local.get $1)
          )
         )
         (else
          (ref.as_non_null
           (array.get $type16
            (struct.get $type14 3
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
     )
     (then
      (if
       (i32.eqz
        (local.get $3)
       )
       (then
        (unreachable)
       )
      )
      (return_call $function40
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
     (else
      (i32.const 0)
     )
    )
   )
  )
 )
