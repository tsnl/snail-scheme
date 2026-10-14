(func $function54 (type $call70) (param $0 (ref null $type54)) (param $1 (ref null $type54)) (result i32)
  (local $2 (ref $type49))
  (local $3 (ref $type49))
  (local $4 (ref $type16))
  (local $5 (ref $type16))
  (local $6 (ref null $type32))
  (local $7 (ref null $type32))
  (local $scratch (ref null $type32))
  (local $scratch_9 (ref null $type54))
  (if (result i32)
   (ref.is_null
    (local.get $0)
   )
   (then
    (ref.is_null
     (local.get $1)
    )
   )
   (else
    (if (result i32)
     (ref.is_null
      (local.get $1)
     )
     (then
      (i32.const 0)
     )
     (else
      (local.set $3
       (struct.get $type54 0
        (local.get $0)
       )
      )
      (local.set $2
       (struct.get $type54 0
        (local.get $1)
       )
      )
      (if
       (i32.eqz
        (global.get $ready145)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global145)
       )
      )
      (if
       (i32.eqz
        (global.get $ready116)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global116)
       )
      )
      (if (result i32)
       (if (result i32)
        (if (result i32)
         (ref.test (ref $type50)
          (local.get $3)
         )
         (then
          (drop
           (ref.cast (ref $type50)
            (local.get $3)
           )
          )
          (i32.const 1)
         )
         (else
          (drop
           (ref.cast (ref $type51)
            (local.get $3)
           )
          )
          (i32.const 0)
         )
        )
        (then
         (if
          (i32.eqz
           (global.get $ready116)
          )
          (then
           (unreachable)
          )
         )
         (drop
          (ref.as_non_null
           (global.get $global116)
          )
         )
         (if (result i32)
          (if (result i32)
           (ref.test (ref $type50)
            (local.get $2)
           )
           (then
            (drop
             (ref.cast (ref $type50)
              (local.get $2)
             )
            )
            (i32.const 1)
           )
           (else
            (drop
             (ref.cast (ref $type51)
              (local.get $2)
             )
            )
            (i32.const 0)
           )
          )
          (then
           (if
            (i32.eqz
             (ref.test (ref $type50)
              (local.get $3)
             )
            )
            (then
             (unreachable)
            )
           )
           (call $function52
            (struct.get $type50 0
             (ref.cast (ref $type50)
              (local.get $3)
             )
            )
            (block (result (ref null $type32))
             (if
              (i32.eqz
               (ref.test (ref $type50)
                (local.get $2)
               )
              )
              (then
               (unreachable)
              )
             )
             (local.set $scratch
              (struct.get $type50 0
               (ref.cast (ref $type50)
                (local.get $2)
               )
              )
             )
             (if
              (i32.eqz
               (global.get $ready142)
              )
              (then
               (unreachable)
              )
             )
             (drop
              (ref.as_non_null
               (global.get $global142)
              )
             )
             (local.get $scratch)
            )
           )
          )
          (else
           (i32.const 0)
          )
         )
        )
        (else
         (if
          (i32.eqz
           (global.get $ready116)
          )
          (then
           (unreachable)
          )
         )
         (drop
          (ref.as_non_null
           (global.get $global116)
          )
         )
         (if (result i32)
          (if (result i32)
           (ref.test (ref $type50)
            (local.get $2)
           )
           (then
            (drop
             (ref.cast (ref $type50)
              (local.get $2)
             )
            )
            (i32.const 1)
           )
           (else
            (drop
             (ref.cast (ref $type51)
              (local.get $2)
             )
            )
            (i32.const 0)
           )
          )
          (then
           (i32.const 0)
          )
          (else
           (if
            (ref.test (ref $type50)
             (local.get $3)
            )
            (then
             (unreachable)
            )
           )
           (local.set $4
            (struct.get $type51 0
             (ref.cast (ref $type51)
              (local.get $3)
             )
            )
           )
           (if
            (ref.test (ref $type50)
             (local.get $2)
            )
            (then
             (unreachable)
            )
           )
           (local.set $5
            (struct.get $type51 0
             (ref.cast (ref $type51)
              (local.get $2)
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
           (if (result i32)
            (i64.eq
             (i64.extend_i32_u
              (struct.get $type16 1
               (local.get $4)
              )
             )
             (i64.extend_i32_u
              (struct.get $type16 1
               (local.get $5)
              )
             )
            )
            (then
             (call $function40
              (local.get $4)
              (local.get $5)
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
         )
        )
       )
       (then
        (return_call $function54
         (struct.get $type54 1
          (local.get $0)
         )
         (block (result (ref null $type54))
          (local.set $scratch_9
           (struct.get $type54 1
            (local.get $1)
           )
          )
          (if
           (i32.eqz
            (global.get $ready148)
           )
           (then
            (unreachable)
           )
          )
          (drop
           (ref.as_non_null
            (global.get $global148)
           )
          )
          (local.get $scratch_9)
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
  )
 )
