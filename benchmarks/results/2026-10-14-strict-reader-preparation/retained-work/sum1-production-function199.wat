(func $function199 (type $call197) (param $0 (ref $type13)) (result f64)
  (local $1 (ref $type24))
  (local $2 (ref $type28))
  (local $3 (ref $type28))
  (local $4 (ref $type27))
  (local $5 i32)
  (drop
   (ref.as_non_null
    (global.get $global422)
   )
  )
  (if (result f64)
   (call $function128
    (local.get $0)
   )
   (then
    (if
     (i32.ne
      (struct.get $type13 0
       (local.get $0)
      )
      (i32.const 5)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global346)
     )
    )
    (if (result f64)
     (local.tee $5
      (struct.get $type24 0
       (local.tee $1
        (struct.get $type23 1
         (ref.cast (ref $type23)
          (local.get $0)
         )
        )
       )
      )
     )
     (then
      (if (result f64)
       (i32.eq
        (local.get $5)
        (i32.const 1)
       )
       (then
        (struct.get $type26 1
         (ref.cast (ref $type26)
          (local.get $1)
         )
        )
       )
       (else
        (local.set $2
         (struct.get $type27 1
          (local.tee $4
           (ref.cast (ref $type27)
            (local.get $1)
           )
          )
         )
        )
        (drop
         (ref.as_non_null
          (global.get $global341)
         )
        )
        (if (result f64)
         (f64.eq
          (if (result f64)
           (ref.test (ref $type29)
            (local.tee $3
             (struct.get $type27 2
              (local.get $4)
             )
            )
           )
           (then
            (f64.convert_i64_s
             (struct.get $type29 0
              (ref.cast (ref $type29)
               (local.get $3)
              )
             )
            )
           )
           (else
            (struct.get $type30 0
             (ref.cast (ref $type30)
              (local.get $3)
             )
            )
           )
          )
          (f64.const 0)
         )
         (then
          (drop
           (ref.as_non_null
            (global.get $global341)
           )
          )
          (if (result f64)
           (ref.test (ref $type29)
            (local.get $2)
           )
           (then
            (f64.convert_i64_s
             (struct.get $type29 0
              (ref.cast (ref $type29)
               (local.get $2)
              )
             )
            )
           )
           (else
            (struct.get $type30 0
             (ref.cast (ref $type30)
              (local.get $2)
             )
            )
           )
          )
         )
         (else
          (drop
           (ref.as_non_null
            (global.get $global323)
           )
          )
          (drop
           (ref.as_non_null
            (global.get $global317)
           )
          )
          (call $snail:datum/fail
           (call $function104
            (global.get $string0)
           )
          )
          (unreachable)
         )
        )
       )
      )
     )
     (else
      (f64.convert_i64_s
       (struct.get $type25 1
        (ref.cast (ref $type25)
         (local.get $1)
        )
       )
      )
     )
    )
   )
   (else
    (drop
     (ref.as_non_null
      (global.get $global323)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global317)
     )
    )
    (call $snail:datum/fail
     (call $function104
      (global.get $string53)
     )
    )
    (unreachable)
   )
  )
 )
