(func $function101 (type $1) (param $0 i64) (param $1 i32) (param $2 i32) (param $3 i64) (param $4 i64) (result i64)
  (local $5 (ref null $type23))
  (local $6 (ref $type42))
  (local $7 (ref $type28))
  (local $8 (ref $type28))
  (local $9 (ref $type14))
  (local $10 (ref $type14))
  (local $11 i64)
  (local $12 i64)
  (local $13 i32)
  (local $scratch i32)
  (if (result i64)
   (i64.gt_s
    (local.get $0)
    (local.get $3)
   )
   (then
    (if
     (i32.eqz
      (global.get $ready312)
     )
     (then
      (unreachable)
     )
    )
    (if
     (i32.eqz
      (global.get $ready320)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global320)
     )
    )
    (drop
     (call $function99
      (call $foreign1
       (global.get $global312)
      )
      (block (result i64)
       (if
        (i32.eqz
         (global.get $ready313)
        )
        (then
         (unreachable)
        )
       )
       (if
        (i32.eqz
         (global.get $ready320)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global320)
        )
       )
       (call $foreign1
        (global.get $global313)
       )
      )
      (block (result (ref $type42))
       (if
        (i32.eqz
         (global.get $ready266)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global266)
        )
       )
       (local.set $4
        (call $function89
         (struct.get $type42 1
          (local.tee $6
           (struct.new $type42
            (ref.func $function89)
            (struct.new $environment89
             (struct.new_default $type63)
             (struct.new $type65
              (struct.new $type66
               (i64.const 1)
              )
             )
             (struct.new $type64
              (i64.const 701)
             )
             (struct.new $type64
              (i64.const 743483)
             )
             (struct.new $type64
              (i64.const 524287)
             )
             (struct.new_default $type63)
            )
           )
          )
         )
         (i64.const 10)
        )
       )
       (if
        (i32.eqz
         (global.get $ready109)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global109)
        )
       )
       (if
        (i64.gt_u
         (local.get $4)
         (i64.const 4294967295)
        )
        (then
         (unreachable)
        )
       )
       (local.set $7
        (call $function93
         (local.get $6)
         (i32.const 1)
         (local.get $4)
         (struct.new $type28
          (array.new_default $type29
           (i32.wrap_i64
            (local.get $4)
           )
          )
         )
         (i32.const 0)
         (i32.const 1)
         (i64.const 0)
        )
       )
       (if
        (i32.eqz
         (global.get $ready207)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global207)
        )
       )
       (if
        (i32.eqz
         (global.get $ready244)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global244)
        )
       )
       (if
        (i32.eqz
         (global.get $ready164)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global164)
        )
       )
       (local.set $8
        (call $function79
         (local.tee $9
          (call $function57
           (local.get $7)
           (i64.extend_i32_u
            (array.len
             (struct.get $type28 0
              (local.get $7)
             )
            )
           )
          )
         )
        )
       )
       (if
        (i32.eqz
         (global.get $ready164)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global164)
        )
       )
       (local.set $10
        (call $function57
         (local.get $8)
         (i64.extend_i32_u
          (array.len
           (struct.get $type28 0
            (local.get $8)
           )
          )
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
       (call $function86
        (block (result i32)
         (local.set $scratch
          (if (result i32)
           (i64.eq
            (i64.extend_i32_u
             (struct.get $type14 1
              (local.get $9)
             )
            )
            (i64.extend_i32_u
             (struct.get $type14 1
              (local.get $10)
             )
            )
           )
           (then
            (call $function40
             (local.get $9)
             (local.get $10)
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
         (if
          (i32.eqz
           (global.get $ready262)
          )
          (then
           (unreachable)
          )
         )
         (drop
          (ref.as_non_null
           (global.get $global262)
          )
         )
         (local.get $scratch)
        )
       )
       (local.get $6)
      )
      (i32.const 1)
      (i32.const 0)
      (i32.const 1)
      (i32.const 0)
      (i32.const 1)
      (i32.const 0)
      (i32.const 1)
      (i64.const 0)
     )
    )
    (if
     (i32.eqz
      (global.get $ready261)
     )
     (then
      (unreachable)
     )
    )
    (local.set $5
     (struct.get $type60 0
      (global.get $global261)
     )
    )
    (if
     (i32.eqz
      (global.get $ready323)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global323)
     )
    )
    (local.set $4
     (if (result i64)
      (ref.is_null
       (local.get $5)
      )
      (then
       (i64.const 0)
      )
      (else
       (if (result i64)
        (ref.is_null
         (local.tee $5
          (struct.get $type23 0
           (local.get $5)
          )
         )
        )
        (then
         (i64.const 1)
        )
        (else
         (if (result i64)
          (ref.is_null
           (local.tee $5
            (struct.get $type23 0
             (local.get $5)
            )
           )
          )
          (then
           (i64.const 2)
          )
          (else
           (if (result i64)
            (ref.is_null
             (local.tee $5
              (struct.get $type23 0
               (local.get $5)
              )
             )
            )
            (then
             (i64.const 3)
            )
            (else
             (if (result i64)
              (ref.is_null
               (local.tee $5
                (struct.get $type23 0
                 (local.get $5)
                )
               )
              )
              (then
               (i64.const 4)
              )
              (else
               (if (result i64)
                (ref.is_null
                 (local.tee $5
                  (struct.get $type23 0
                   (local.get $5)
                  )
                 )
                )
                (then
                 (i64.const 5)
                )
                (else
                 (if (result i64)
                  (ref.is_null
                   (local.tee $5
                    (struct.get $type23 0
                     (local.get $5)
                    )
                   )
                  )
                  (then
                   (i64.const 6)
                  )
                  (else
                   (if (result i64)
                    (ref.is_null
                     (local.tee $5
                      (struct.get $type23 0
                       (local.get $5)
                      )
                     )
                    )
                    (then
                     (i64.const 7)
                    )
                    (else
                     (if (result i64)
                      (ref.is_null
                       (local.tee $5
                        (struct.get $type23 0
                         (local.get $5)
                        )
                       )
                      )
                      (then
                       (i64.const 8)
                      )
                      (else
                       (if (result i64)
                        (ref.is_null
                         (local.tee $5
                          (struct.get $type23 0
                           (local.get $5)
                          )
                         )
                        )
                        (then
                         (i64.const 9)
                        )
                        (else
                         (if (result i64)
                          (ref.is_null
                           (local.tee $5
                            (struct.get $type23 0
                             (local.get $5)
                            )
                           )
                          )
                          (then
                           (i64.const 10)
                          )
                          (else
                           (if (result i64)
                            (ref.is_null
                             (local.tee $5
                              (struct.get $type23 0
                               (local.get $5)
                              )
                             )
                            )
                            (then
                             (i64.const 11)
                            )
                            (else
                             (if (result i64)
                              (ref.is_null
                               (local.tee $5
                                (struct.get $type23 0
                                 (local.get $5)
                                )
                               )
                              )
                              (then
                               (i64.const 12)
                              )
                              (else
                               (if (result i64)
                                (ref.is_null
                                 (local.tee $5
                                  (struct.get $type23 0
                                   (local.get $5)
                                  )
                                 )
                                )
                                (then
                                 (i64.const 13)
                                )
                                (else
                                 (call $function104
                                  (i32.const 0)
                                  (i32.const 1)
                                  (struct.get $type23 0
                                   (local.get $5)
                                  )
                                  (i64.const 14)
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
      (local.get $2)
     )
     (then
      (unreachable)
     )
    )
    (return_call $function101
     (local.get $0)
     (local.get $1)
     (local.get $2)
     (i64.add
      (local.get $3)
      (i64.const 1)
     )
     (local.get $4)
    )
   )
   (else
    (i64.extend_i32_u
     (i32.ne
      (if (result i32)
       (i64.gt_s
        (local.get $3)
        (i64.const 0)
       )
       (then
        (if
         (i32.eqz
          (global.get $ready314)
         )
         (then
          (unreachable)
         )
        )
        (i64.eq
         (global.get $global314)
         (local.get $4)
        )
       )
       (else
        (i32.const 0)
       )
      )
      (i32.const 0)
     )
    )
   )
  )
 )
