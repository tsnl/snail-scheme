(func $function152 (type $call103) (param $0 (ref null $type32)) (param $1 (ref $type104)) (result (ref $type104))
  (local $2 (ref null $type32))
  (local $3 (ref null $type54))
  (local $4 i64)
  (local $5 i64)
  (if
   (i32.eqz
    (global.get $ready462)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global462)
   )
  )
  (if (result (ref $type104))
   (i64.lt_s
    (local.tee $4
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
         (local.tee $2
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
           (local.tee $2
            (struct.get $type32 1
             (local.get $2)
            )
           )
          )
          (then
           (i64.const 2)
          )
          (else
           (if (result i64)
            (ref.is_null
             (local.tee $2
              (struct.get $type32 1
               (local.get $2)
              )
             )
            )
            (then
             (i64.const 3)
            )
            (else
             (if (result i64)
              (ref.is_null
               (local.tee $2
                (struct.get $type32 1
                 (local.get $2)
                )
               )
              )
              (then
               (i64.const 4)
              )
              (else
               (if (result i64)
                (ref.is_null
                 (local.tee $2
                  (struct.get $type32 1
                   (local.get $2)
                  )
                 )
                )
                (then
                 (i64.const 5)
                )
                (else
                 (if (result i64)
                  (ref.is_null
                   (local.tee $2
                    (struct.get $type32 1
                     (local.get $2)
                    )
                   )
                  )
                  (then
                   (i64.const 6)
                  )
                  (else
                   (if (result i64)
                    (ref.is_null
                     (local.tee $2
                      (struct.get $type32 1
                       (local.get $2)
                      )
                     )
                    )
                    (then
                     (i64.const 7)
                    )
                    (else
                     (if (result i64)
                      (ref.is_null
                       (local.tee $2
                        (struct.get $type32 1
                         (local.get $2)
                        )
                       )
                      )
                      (then
                       (i64.const 8)
                      )
                      (else
                       (call $function154
                        (i32.const 0)
                        (i32.const 1)
                        (struct.get $type32 1
                         (local.get $2)
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
    (local.tee $5
     (struct.get $type104 0
      (local.get $1)
     )
    )
   )
   (then
    (local.get $1)
   )
   (else
    (if (result (ref $type104))
     (i64.eq
      (local.get $4)
      (local.get $5)
     )
     (then
      (local.set $3
       (struct.get $type104 2
        (local.get $1)
       )
      )
      (struct.new $type104
       (local.get $5)
       (local.tee $4
        (i64.add
         (struct.get $type104 1
          (local.get $1)
         )
         (i64.const 1)
        )
       )
       (if (result (ref null $type54))
        (i64.lt_s
         (local.get $4)
         (i64.const 3000)
        )
        (then
         (struct.new $type54
          (struct.new $type50
           (local.get $0)
          )
          (local.get $3)
         )
        )
        (else
         (if (result (ref null $type54))
          (i64.eq
           (local.get $4)
           (i64.const 3000)
          )
          (then
           (struct.new $type54
            (struct.new $type51
             (global.get $string1)
            )
            (local.get $3)
           )
          )
          (else
           (local.get $3)
          )
         )
        )
       )
      )
     )
     (else
      (if
       (i32.eqz
        (global.get $ready470)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global470)
       )
      )
      (struct.new $type104
       (local.get $4)
       (i64.const 1)
       (struct.new $type54
        (struct.new $type50
         (local.get $0)
        )
        (ref.null none)
       )
      )
     )
    )
   )
  )
 )
