(func $function153 (type $call31) (param $0 (ref null $type32)) (result i64)
  (if (result i64)
   (ref.is_null
    (local.get $0)
   )
   (then
    (i64.const 0)
   )
   (else
    (if (result i64)
     (ref.is_null
      (local.tee $0
       (struct.get $type32 1
        (local.get $0)
       )
      )
     )
     (then
      (i64.const 1)
     )
     (else
      (if (result i64)
       (ref.is_null
        (local.tee $0
         (struct.get $type32 1
          (local.get $0)
         )
        )
       )
       (then
        (i64.const 2)
       )
       (else
        (if (result i64)
         (ref.is_null
          (local.tee $0
           (struct.get $type32 1
            (local.get $0)
           )
          )
         )
         (then
          (i64.const 3)
         )
         (else
          (if (result i64)
           (ref.is_null
            (local.tee $0
             (struct.get $type32 1
              (local.get $0)
             )
            )
           )
           (then
            (i64.const 4)
           )
           (else
            (if (result i64)
             (ref.is_null
              (local.tee $0
               (struct.get $type32 1
                (local.get $0)
               )
              )
             )
             (then
              (i64.const 5)
             )
             (else
              (if (result i64)
               (ref.is_null
                (local.tee $0
                 (struct.get $type32 1
                  (local.get $0)
                 )
                )
               )
               (then
                (i64.const 6)
               )
               (else
                (if (result i64)
                 (ref.is_null
                  (local.tee $0
                   (struct.get $type32 1
                    (local.get $0)
                   )
                  )
                 )
                 (then
                  (i64.const 7)
                 )
                 (else
                  (if (result i64)
                   (ref.is_null
                    (local.tee $0
                     (struct.get $type32 1
                      (local.get $0)
                     )
                    )
                   )
                   (then
                    (i64.const 8)
                   )
                   (else
                    (return_call $function154
                     (i32.const 0)
                     (i32.const 1)
                     (struct.get $type32 1
                      (local.get $0)
                     )
                     (i64.const 9)
                    )
                   )
                  )
                 )
                )
               )
              )
             )
            )
           )
          )
         )
        )
       )
      )
     )
    )
   )
  )
 )
