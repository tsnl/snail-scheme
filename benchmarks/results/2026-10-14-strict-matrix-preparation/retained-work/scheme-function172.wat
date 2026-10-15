(func $function172 (type $12) (param $0 i64) (param $1 (ref $type103)) (param $2 (ref $type93)) (param $3 i32) (param $4 i32) (param $5 i32) (param $6 i64) (param $7 (ref null $type32)) (param $8 i32) (param $9 i32) (param $10 (ref null $type32)) (param $11 (ref $type104)) (result (ref $type104))
  (local $12 (ref $type32))
  (local $13 (ref $type32))
  (local $14 (ref null $type32))
  (local $15 (ref null $type30))
  (local $16 (ref $type114))
  (if (result (ref $type104))
   (ref.is_null
    (local.get $10)
   )
   (then
    (local.get $11)
   )
   (else
    (local.set $14
     (struct.get $type32 1
      (local.get $10)
     )
    )
    (local.set $12
     (struct.new $type32
      (struct.get $type32 0
       (local.tee $13
        (struct.new $type32
         (struct.get $type32 0
          (local.get $10)
         )
         (block (result (ref null $type32))
          (if
           (i32.eqz
            (global.get $ready269)
           )
           (then
            (unreachable)
           )
          )
          (drop
           (struct.get $type55 1
            (global.get $global269)
           )
          )
          (local.get $7)
         )
        )
       )
      )
      (ref.null none)
     )
    )
    (local.set $10
     (if (result (ref null $type32))
      (ref.is_null
       (local.tee $10
        (struct.get $type32 1
         (local.get $13)
        )
       )
      )
      (then
       (local.get $12)
      )
      (else
       (local.set $12
        (struct.new $type32
         (struct.get $type32 0
          (local.get $10)
         )
         (local.get $12)
        )
       )
       (if (result (ref null $type32))
        (ref.is_null
         (local.tee $10
          (struct.get $type32 1
           (local.get $10)
          )
         )
        )
        (then
         (local.get $12)
        )
        (else
         (local.set $12
          (struct.new $type32
           (struct.get $type32 0
            (local.get $10)
           )
           (local.get $12)
          )
         )
         (if (result (ref null $type32))
          (ref.is_null
           (local.tee $10
            (struct.get $type32 1
             (local.get $10)
            )
           )
          )
          (then
           (local.get $12)
          )
          (else
           (local.set $12
            (struct.new $type32
             (struct.get $type32 0
              (local.get $10)
             )
             (local.get $12)
            )
           )
           (if (result (ref null $type32))
            (ref.is_null
             (local.tee $10
              (struct.get $type32 1
               (local.get $10)
              )
             )
            )
            (then
             (local.get $12)
            )
            (else
             (local.set $12
              (struct.new $type32
               (struct.get $type32 0
                (local.get $10)
               )
               (local.get $12)
              )
             )
             (if (result (ref null $type32))
              (ref.is_null
               (local.tee $10
                (struct.get $type32 1
                 (local.get $10)
                )
               )
              )
              (then
               (local.get $12)
              )
              (else
               (local.set $12
                (struct.new $type32
                 (struct.get $type32 0
                  (local.get $10)
                 )
                 (local.get $12)
                )
               )
               (if (result (ref null $type32))
                (ref.is_null
                 (local.tee $10
                  (struct.get $type32 1
                   (local.get $10)
                  )
                 )
                )
                (then
                 (local.get $12)
                )
                (else
                 (local.set $12
                  (struct.new $type32
                   (struct.get $type32 0
                    (local.get $10)
                   )
                   (local.get $12)
                  )
                 )
                 (if (result (ref null $type32))
                  (ref.is_null
                   (local.tee $10
                    (struct.get $type32 1
                     (local.get $10)
                    )
                   )
                  )
                  (then
                   (local.get $12)
                  )
                  (else
                   (local.set $12
                    (struct.new $type32
                     (struct.get $type32 0
                      (local.get $10)
                     )
                     (local.get $12)
                    )
                   )
                   (if (result (ref null $type32))
                    (ref.is_null
                     (local.tee $10
                      (struct.get $type32 1
                       (local.get $10)
                      )
                     )
                    )
                    (then
                     (local.get $12)
                    )
                    (else
                     (call $function92
                      (i32.const 0)
                      (i32.const 1)
                      (struct.get $type32 1
                       (local.get $10)
                      )
                      (struct.new $type32
                       (struct.get $type32 0
                        (local.get $10)
                       )
                       (local.get $12)
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
    (if
     (i32.eqz
      (global.get $ready173)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (struct.get $type77 1
      (global.get $global173)
     )
    )
    (if
     (i32.eqz
      (global.get $ready175)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global175)
     )
    )
    (local.set $16
     (struct.new $type114
      (i32.const 1)
     )
    )
    (if
     (call $function67
      (local.get $10)
      (i32.const 0)
      (i32.const 1)
      (if (result (ref $type35))
       (ref.is_null
        (local.get $10)
       )
       (then
        (global.get $empty36)
       )
       (else
        (struct.new $type37
         (struct.new $type38
          (struct.new $environment64
           (local.get $16)
           (local.get $10)
           (ref.null none)
          )
         )
        )
       )
      )
     )
     (then
      (if
       (i32.eqz
        (local.get $5)
       )
       (then
        (unreachable)
       )
      )
      (local.set $11
       (call $function169
        (local.get $0)
        (local.get $1)
        (local.get $2)
        (local.get $3)
        (local.get $4)
        (local.get $5)
        (i64.add
         (local.get $6)
         (i64.const 1)
        )
        (local.get $13)
        (local.get $14)
        (local.get $11)
       )
      )
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
    (return_call $function172
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
     (local.get $14)
     (local.get $11)
    )
   )
  )
 )
