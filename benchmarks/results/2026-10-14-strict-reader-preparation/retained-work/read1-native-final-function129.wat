(func $function129 (type $call134) (param $0 (ref $type13)) (param $1 (ref $type13)) (result i32)
  (local $2 (ref $type24))
  (local $3 (ref $type24))
  (local $4 (ref $type27))
  (local $5 (ref $type18))
  (local $6 (ref $type18))
  (local $7 (ref $type34))
  (local $8 (ref $type34))
  (local $9 (ref $type36))
  (local $10 (ref $type36))
  (local $11 (ref $type22))
  (local $12 (ref $type28))
  (local $13 (ref $type31))
  (local $14 (ref $type32))
  (local $15 i32)
  (local $16 i64)
  (local $scratch (ref $type22))
  (drop
   (ref.as_non_null
    (global.get $global410)
   )
  )
  (if (result i32)
   (i64.eq
    (call $function127
     (local.get $0)
    )
    (block (result i64)
     (drop
      (ref.as_non_null
       (global.get $global410)
      )
     )
     (call $function127
      (local.get $1)
     )
    )
   )
   (then
    (if (result i32)
     (local.tee $15
      (struct.get $type13 0
       (local.get $0)
      )
     )
     (then
      (if (result i32)
       (i32.eq
        (local.get $15)
        (i32.const 1)
       )
       (then
        (if (result i32)
         (struct.get $type15 1
          (ref.cast (ref $type15)
           (local.get $0)
          )
         )
         (then
          (if
           (i32.ne
            (struct.get $type13 0
             (local.get $1)
            )
            (i32.const 1)
           )
           (then
            (unreachable)
           )
          )
          (struct.get $type15 1
           (ref.cast (ref $type15)
            (local.get $1)
           )
          )
         )
         (else
          (if
           (i32.ne
            (struct.get $type13 0
             (local.get $1)
            )
            (i32.const 1)
           )
           (then
            (unreachable)
           )
          )
          (i32.eqz
           (struct.get $type15 1
            (ref.cast (ref $type15)
             (local.get $1)
            )
           )
          )
         )
        )
       )
       (else
        (if (result i32)
         (i32.eq
          (struct.get $type13 0
           (local.get $0)
          )
          (i32.const 2)
         )
         (then
          (local.set $15
           (struct.get $type16 1
            (ref.cast (ref $type16)
             (local.get $0)
            )
           )
          )
          (if
           (i32.ne
            (struct.get $type13 0
             (local.get $1)
            )
            (i32.const 2)
           )
           (then
            (unreachable)
           )
          )
          (i32.eq
           (struct.get $type16 1
            (ref.cast (ref $type16)
             (local.get $1)
            )
           )
           (local.get $15)
          )
         )
         (else
          (if (result i32)
           (i32.eq
            (struct.get $type13 0
             (local.get $0)
            )
            (i32.const 3)
           )
           (then
            (local.set $5
             (struct.get $type17 1
              (ref.cast (ref $type17)
               (local.get $0)
              )
             )
            )
            (if
             (i32.ne
              (struct.get $type13 0
               (local.get $1)
              )
              (i32.const 3)
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
               (struct.get $type18 1
                (local.get $5)
               )
              )
              (i64.extend_i32_u
               (struct.get $type18 1
                (local.tee $6
                 (struct.get $type17 1
                  (ref.cast (ref $type17)
                   (local.get $1)
                  )
                 )
                )
               )
              )
             )
             (then
              (return_call $function40
               (local.get $5)
               (local.get $6)
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
           (else
            (if (result i32)
             (i32.eq
              (struct.get $type13 0
               (local.get $0)
              )
              (i32.const 4)
             )
             (then
              (i32.eq
               (struct.get $type22 0
                (block (result (ref $type22))
                 (local.set $scratch
                  (struct.get $type21 1
                   (ref.cast (ref $type21)
                    (local.get $0)
                   )
                  )
                 )
                 (if
                  (i32.ne
                   (struct.get $type13 0
                    (local.get $1)
                   )
                   (i32.const 4)
                  )
                  (then
                   (unreachable)
                  )
                 )
                 (drop
                  (ref.as_non_null
                   (global.get $global331)
                  )
                 )
                 (local.get $scratch)
                )
               )
               (struct.get $type22 0
                (struct.get $type21 1
                 (ref.cast (ref $type21)
                  (local.get $1)
                 )
                )
               )
              )
             )
             (else
              (if (result i32)
               (i32.eq
                (struct.get $type13 0
                 (local.get $0)
                )
                (i32.const 5)
               )
               (then
                (local.set $3
                 (struct.get $type23 1
                  (ref.cast (ref $type23)
                   (local.get $0)
                  )
                 )
                )
                (if
                 (i32.ne
                  (struct.get $type13 0
                   (local.get $1)
                  )
                  (i32.const 5)
                 )
                 (then
                  (unreachable)
                 )
                )
                (drop
                 (ref.as_non_null
                  (global.get $global389)
                 )
                )
                (local.set $2
                 (struct.get $type23 1
                  (ref.cast (ref $type23)
                   (local.get $1)
                  )
                 )
                )
                (drop
                 (ref.as_non_null
                  (global.get $global382)
                 )
                )
                (if (result i32)
                 (i64.eq
                  (if (result i64)
                   (local.tee $15
                    (struct.get $type24 0
                     (local.get $3)
                    )
                   )
                   (then
                    (if (result i64)
                     (i32.eq
                      (local.get $15)
                      (i32.const 1)
                     )
                     (then
                      (drop
                       (ref.cast (ref $type26)
                        (local.get $3)
                       )
                      )
                      (i64.const 1)
                     )
                     (else
                      (drop
                       (ref.cast (ref $type27)
                        (local.get $3)
                       )
                      )
                      (i64.const 2)
                     )
                    )
                   )
                   (else
                    (drop
                     (ref.cast (ref $type25)
                      (local.get $3)
                     )
                    )
                    (i64.const 0)
                   )
                  )
                  (if (result i64)
                   (local.tee $15
                    (struct.get $type24 0
                     (local.get $2)
                    )
                   )
                   (then
                    (if (result i64)
                     (i32.eq
                      (local.get $15)
                      (i32.const 1)
                     )
                     (then
                      (drop
                       (ref.cast (ref $type26)
                        (local.get $2)
                       )
                      )
                      (i64.const 1)
                     )
                     (else
                      (drop
                       (ref.cast (ref $type27)
                        (local.get $2)
                       )
                      )
                      (i64.const 2)
                     )
                    )
                   )
                   (else
                    (drop
                     (ref.cast (ref $type25)
                      (local.get $2)
                     )
                    )
                    (i64.const 0)
                   )
                  )
                 )
                 (then
                  (if (result i32)
                   (local.tee $15
                    (struct.get $type24 0
                     (local.get $3)
                    )
                   )
                   (then
                    (if (result i32)
                     (i32.eq
                      (local.get $15)
                      (i32.const 1)
                     )
                     (then
                      (if
                       (i32.ne
                        (struct.get $type24 0
                         (local.get $2)
                        )
                        (i32.const 1)
                       )
                       (then
                        (unreachable)
                       )
                      )
                      (i32.eq
                       (call $foreign24
                        (struct.get $type26 1
                         (ref.cast (ref $type26)
                          (local.get $3)
                         )
                        )
                        (struct.get $type26 1
                         (ref.cast (ref $type26)
                          (local.get $2)
                         )
                        )
                       )
                       (i32.const 1)
                      )
                     )
                     (else
                      (local.set $12
                       (struct.get $type27 2
                        (local.tee $4
                         (ref.cast (ref $type27)
                          (local.get $3)
                         )
                        )
                       )
                      )
                      (if
                       (i32.ne
                        (struct.get $type24 0
                         (local.get $2)
                        )
                        (i32.const 2)
                       )
                       (then
                        (unreachable)
                       )
                      )
                      (drop
                       (ref.as_non_null
                        (global.get $global370)
                       )
                      )
                      (if (result i32)
                       (call $function119
                        (struct.get $type27 1
                         (local.get $4)
                        )
                        (struct.get $type27 1
                         (local.tee $4
                          (ref.cast (ref $type27)
                           (local.get $2)
                          )
                         )
                        )
                       )
                       (then
                        (drop
                         (ref.as_non_null
                          (global.get $global370)
                         )
                        )
                        (return_call $function119
                         (local.get $12)
                         (struct.get $type27 2
                          (local.get $4)
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
                   (else
                    (local.set $16
                     (struct.get $type25 1
                      (ref.cast (ref $type25)
                       (local.get $3)
                      )
                     )
                    )
                    (if
                     (struct.get $type24 0
                      (local.get $2)
                     )
                     (then
                      (unreachable)
                     )
                    )
                    (i64.eq
                     (struct.get $type25 1
                      (ref.cast (ref $type25)
                       (local.get $2)
                      )
                     )
                     (local.get $16)
                    )
                   )
                  )
                 )
                 (else
                  (i32.const 0)
                 )
                )
               )
               (else
                (if (result i32)
                 (i32.eq
                  (struct.get $type13 0
                   (local.get $0)
                  )
                  (i32.const 6)
                 )
                 (then
                  (local.set $14
                   (struct.get $type31 2
                    (local.tee $13
                     (ref.cast (ref $type31)
                      (local.get $0)
                     )
                    )
                   )
                  )
                  (drop
                   (ref.as_non_null
                    (global.get $global400)
                   )
                  )
                  (if
                   (i32.ne
                    (struct.get $type13 0
                     (local.get $1)
                    )
                    (i32.const 6)
                   )
                   (then
                    (unreachable)
                   )
                  )
                  (local.set $0
                   (struct.get $type32 0
                    (struct.get $type31 1
                     (ref.cast (ref $type31)
                      (local.get $1)
                     )
                    )
                   )
                  )
                  (if
                   (i32.eqz
                    (global.get $ready424)
                   )
                   (then
                    (unreachable)
                   )
                  )
                  (drop
                   (ref.as_non_null
                    (global.get $global424)
                   )
                  )
                  (if (result i32)
                   (call $function129
                    (struct.get $type32 0
                     (struct.get $type31 1
                      (local.get $13)
                     )
                    )
                    (local.get $0)
                   )
                   (then
                    (drop
                     (ref.as_non_null
                      (global.get $global402)
                     )
                    )
                    (if
                     (i32.ne
                      (struct.get $type13 0
                       (local.get $1)
                      )
                      (i32.const 6)
                     )
                     (then
                      (unreachable)
                     )
                    )
                    (local.set $0
                     (struct.get $type32 0
                      (struct.get $type31 2
                       (ref.cast (ref $type31)
                        (local.get $1)
                       )
                      )
                     )
                    )
                    (if
                     (i32.eqz
                      (global.get $ready424)
                     )
                     (then
                      (unreachable)
                     )
                    )
                    (drop
                     (ref.as_non_null
                      (global.get $global424)
                     )
                    )
                    (return_call $function129
                     (struct.get $type32 0
                      (local.get $14)
                     )
                     (local.get $0)
                    )
                   )
                   (else
                    (i32.const 0)
                   )
                  )
                 )
                 (else
                  (if (result i32)
                   (i32.eq
                    (struct.get $type13 0
                     (local.get $0)
                    )
                    (i32.const 7)
                   )
                   (then
                    (local.set $7
                     (struct.get $type33 1
                      (ref.cast (ref $type33)
                       (local.get $0)
                      )
                     )
                    )
                    (if
                     (i32.ne
                      (struct.get $type13 0
                       (local.get $1)
                      )
                      (i32.const 7)
                     )
                     (then
                      (unreachable)
                     )
                    )
                    (local.set $8
                     (struct.get $type33 1
                      (ref.cast (ref $type33)
                       (local.get $1)
                      )
                     )
                    )
                    (if
                     (i32.eqz
                      (global.get $ready436)
                     )
                     (then
                      (unreachable)
                     )
                    )
                    (drop
                     (ref.as_non_null
                      (global.get $global436)
                     )
                    )
                    (if (result i32)
                     (i64.eq
                      (local.tee $16
                       (i64.extend_i32_u
                        (array.len
                         (local.get $7)
                        )
                       )
                      )
                      (i64.extend_i32_u
                       (array.len
                        (local.get $8)
                       )
                      )
                     )
                     (then
                      (return_call $function131
                       (local.get $7)
                       (local.get $8)
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
                   (else
                    (local.set $9
                     (struct.get $type35 1
                      (ref.cast (ref $type35)
                       (local.get $0)
                      )
                     )
                    )
                    (if
                     (i32.ne
                      (struct.get $type13 0
                       (local.get $1)
                      )
                      (i32.const 8)
                     )
                     (then
                      (unreachable)
                     )
                    )
                    (local.set $10
                     (struct.get $type35 1
                      (ref.cast (ref $type35)
                       (local.get $1)
                      )
                     )
                    )
                    (if
                     (i32.eqz
                      (global.get $ready444)
                     )
                     (then
                      (unreachable)
                     )
                    )
                    (drop
                     (ref.as_non_null
                      (global.get $global444)
                     )
                    )
                    (if (result i32)
                     (i64.eq
                      (local.tee $16
                       (i64.extend_i32_u
                        (array.len
                         (struct.get $type36 0
                          (local.get $9)
                         )
                        )
                       )
                      )
                      (i64.extend_i32_u
                       (array.len
                        (struct.get $type36 0
                         (local.get $10)
                        )
                       )
                      )
                     )
                     (then
                      (return_call $function133
                       (local.get $9)
                       (local.get $10)
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
     (else
      (i32.const 1)
     )
    )
   )
   (else
    (i32.const 0)
   )
  )
 )
