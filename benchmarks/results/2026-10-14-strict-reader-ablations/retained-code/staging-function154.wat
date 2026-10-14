(func $function154 (type $call162) (param $0 (ref $type58)) (result (ref $type163))
  (local $1 i32)
  (local $2 i32)
  (local $3 i32)
  (local $4 i32)
  (local $5 i32)
  (local $6 i32)
  (local $7 i32)
  (local $8 i32)
  (local $9 i32)
  (local $10 i64)
  (local $11 (ref $type18))
  (local $12 (ref $type18))
  (local $13 (ref $type18))
  (local $14 (ref $type68))
  (local $15 (ref $type121))
  (local $16 (ref $type154))
  (local $17 (ref $type130))
  (local $18 (ref $type181))
  (local $19 (ref $type163))
  (local $scratch i32)
  (drop
   (ref.as_non_null
    (global.get $global530)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global135)
   )
  )
  (local.set $1
   (call $snail:io/read-character
    (struct.get $type56 0
     (struct.get $type58 0
      (local.get $0)
     )
    )
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global133)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global532)
   )
  )
  (block $block
   (return
    (if (result (ref $type165))
     (i64.lt_s
      (local.tee $10
       (if (result i64)
        (ref.test (ref $type69)
         (local.tee $14
          (if (result (ref $type68))
           (i32.eq
            (local.get $1)
            (i32.const -1)
           )
           (then
            (global.get $empty69)
           )
           (else
            (if
             (i64.gt_u
              (local.tee $10
               (i64.extend_i32_s
                (local.get $1)
               )
              )
              (i64.const 1114111)
             )
             (then
              (unreachable)
             )
            )
            (if
             (i32.and
              (i64.le_u
               (local.get $10)
               (i64.const 57343)
              )
              (i64.ge_u
               (local.get $10)
               (i64.const 55296)
              )
             )
             (then
              (unreachable)
             )
            )
            (struct.new $type70
             (i32.wrap_i64
              (local.get $10)
             )
            )
           )
          )
         )
        )
        (then
         (i64.const -1)
        )
        (else
         (i64.extend_i32_u
          (struct.get $type70 0
           (ref.cast (ref $type70)
            (local.get $14)
           )
          )
         )
        )
       )
      )
      (i64.const 0)
     )
     (then
      (global.get $empty165)
     )
     (else
      (drop
       (ref.as_non_null
        (global.get $global536)
       )
      )
      (br_if $block
       (if (result i32)
        (i64.ge_s
         (local.get $10)
         (i64.const 0)
        )
        (then
         (if
          (i64.gt_u
           (local.get $10)
           (i64.const 1114111)
          )
          (then
           (unreachable)
          )
         )
         (if
          (i32.and
           (i64.le_u
            (local.get $10)
            (i64.const 57343)
           )
           (i64.ge_u
            (local.get $10)
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
            (local.get $10)
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
      (drop
       (ref.as_non_null
        (global.get $global538)
       )
      )
      (if
       (i64.eq
        (local.get $10)
        (i64.const 59)
       )
       (then
        (drop
         (ref.as_non_null
          (global.get $global541)
         )
        )
        (drop
         (call $function159
          (local.get $0)
         )
        )
        (br $block)
       )
       (else
        (if
         (i32.eqz
          (global.get $ready546)
         )
         (then
          (unreachable)
         )
        )
        (drop
         (ref.as_non_null
          (global.get $global546)
         )
        )
        (drop
         (ref.as_non_null
          (global.get $global538)
         )
        )
        (return
         (if (result (ref $type163))
          (i64.eq
           (local.get $10)
           (i64.const 40)
          )
          (then
           (struct.new $type168
            (i32.const 4)
            (i64.const 0)
           )
          )
          (else
           (drop
            (ref.as_non_null
             (global.get $global538)
            )
           )
           (if (result (ref $type163))
            (i64.eq
             (local.get $10)
             (i64.const 41)
            )
            (then
             (global.get $empty166)
            )
            (else
             (drop
              (ref.as_non_null
               (global.get $global538)
              )
             )
             (if (result (ref $type163))
              (i64.eq
               (local.get $10)
               (i64.const 39)
              )
              (then
               (struct.new $type169
                (i32.const 5)
                (global.get $string8)
               )
              )
              (else
               (drop
                (ref.as_non_null
                 (global.get $global538)
                )
               )
               (if (result (ref $type163))
                (i64.eq
                 (local.get $10)
                 (i64.const 96)
                )
                (then
                 (struct.new $type169
                  (i32.const 5)
                  (global.get $string7)
                 )
                )
                (else
                 (drop
                  (ref.as_non_null
                   (global.get $global538)
                  )
                 )
                 (if (result (ref $type163))
                  (i64.eq
                   (local.get $10)
                   (i64.const 44)
                  )
                  (then
                   (drop
                    (ref.as_non_null
                     (global.get $global549)
                    )
                   )
                   (drop
                    (ref.as_non_null
                     (global.get $global552)
                    )
                   )
                   (drop
                    (ref.as_non_null
                     (global.get $global137)
                    )
                   )
                   (local.set $1
                    (call $snail:io/peek-character
                     (struct.get $type56 0
                      (struct.get $type58 0
                       (local.get $0)
                      )
                     )
                    )
                   )
                   (drop
                    (ref.as_non_null
                     (global.get $global133)
                    )
                   )
                   (drop
                    (ref.as_non_null
                     (global.get $global532)
                    )
                   )
                   (drop
                    (ref.as_non_null
                     (global.get $global538)
                    )
                   )
                   (struct.new $type169
                    (i32.const 5)
                    (select (result (ref $type18))
                     (global.get $string6)
                     (global.get $string5)
                     (if (result i32)
                      (i64.eq
                       (if (result i64)
                        (ref.test (ref $type69)
                         (local.tee $14
                          (if (result (ref $type68))
                           (i32.eq
                            (local.get $1)
                            (i32.const -1)
                           )
                           (then
                            (global.get $empty69)
                           )
                           (else
                            (if
                             (i64.gt_u
                              (local.tee $10
                               (i64.extend_i32_s
                                (local.get $1)
                               )
                              )
                              (i64.const 1114111)
                             )
                             (then
                              (unreachable)
                             )
                            )
                            (if
                             (i32.and
                              (i64.le_u
                               (local.get $10)
                               (i64.const 57343)
                              )
                              (i64.ge_u
                               (local.get $10)
                               (i64.const 55296)
                              )
                             )
                             (then
                              (unreachable)
                             )
                            )
                            (struct.new $type70
                             (i32.wrap_i64
                              (local.get $10)
                             )
                            )
                           )
                          )
                         )
                        )
                        (then
                         (i64.const -1)
                        )
                        (else
                         (i64.extend_i32_u
                          (struct.get $type70 0
                           (ref.cast (ref $type70)
                            (local.get $14)
                           )
                          )
                         )
                        )
                       )
                       (i64.const 64)
                      )
                      (then
                       (drop
                        (ref.as_non_null
                         (global.get $global135)
                        )
                       )
                       (local.set $1
                        (call $snail:io/read-character
                         (struct.get $type56 0
                          (struct.get $type58 0
                           (local.get $0)
                          )
                         )
                        )
                       )
                       (drop
                        (ref.as_non_null
                         (global.get $global133)
                        )
                       )
                       (drop
                        (if (result (ref $type68))
                         (i32.eq
                          (local.get $1)
                          (i32.const -1)
                         )
                         (then
                          (global.get $empty69)
                         )
                         (else
                          (if
                           (i64.gt_u
                            (local.tee $10
                             (i64.extend_i32_s
                              (local.get $1)
                             )
                            )
                            (i64.const 1114111)
                           )
                           (then
                            (unreachable)
                           )
                          )
                          (if
                           (i32.and
                            (i64.le_u
                             (local.get $10)
                             (i64.const 57343)
                            )
                            (i64.ge_u
                             (local.get $10)
                             (i64.const 55296)
                            )
                           )
                           (then
                            (unreachable)
                           )
                          )
                          (struct.new $type70
                           (i32.wrap_i64
                            (local.get $10)
                           )
                          )
                         )
                        )
                       )
                       (i32.const 1)
                      )
                      (else
                       (i32.const 0)
                      )
                     )
                    )
                   )
                  )
                  (else
                   (drop
                    (ref.as_non_null
                     (global.get $global538)
                    )
                   )
                   (if (result (ref $type170))
                    (i64.eq
                     (local.get $10)
                     (i64.const 34)
                    )
                    (then
                     (if
                      (i32.eqz
                       (global.get $ready554)
                      )
                      (then
                       (unreachable)
                      )
                     )
                     (drop
                      (ref.as_non_null
                       (global.get $global554)
                      )
                     )
                     (return_call $function163
                      (local.get $0)
                      (i32.const 34)
                      (i32.const 0)
                     )
                    )
                    (else
                     (drop
                      (ref.as_non_null
                       (global.get $global538)
                      )
                     )
                     (if (result (ref $type170))
                      (i64.eq
                       (local.get $10)
                       (i64.const 124)
                      )
                      (then
                       (if
                        (i32.eqz
                         (global.get $ready554)
                        )
                        (then
                         (unreachable)
                        )
                       )
                       (drop
                        (ref.as_non_null
                         (global.get $global554)
                        )
                       )
                       (return_call $function163
                        (local.get $0)
                        (i32.const 124)
                        (i32.const 1)
                       )
                      )
                      (else
                       (drop
                        (ref.as_non_null
                         (global.get $global538)
                        )
                       )
                       (if (result (ref $type170))
                        (i64.eq
                         (local.get $10)
                         (i64.const 35)
                        )
                        (then
                         (if
                          (i32.eqz
                           (global.get $ready627)
                          )
                          (then
                           (unreachable)
                          )
                         )
                         (drop
                          (ref.as_non_null
                           (global.get $global627)
                          )
                         )
                         (drop
                          (ref.as_non_null
                           (global.get $global530)
                          )
                         )
                         (drop
                          (ref.as_non_null
                           (global.get $global135)
                          )
                         )
                         (local.set $1
                          (call $snail:io/read-character
                           (struct.get $type56 0
                            (struct.get $type58 0
                             (local.get $0)
                            )
                           )
                          )
                         )
                         (drop
                          (ref.as_non_null
                           (global.get $global133)
                          )
                         )
                         (drop
                          (ref.as_non_null
                           (global.get $global532)
                          )
                         )
                         (return
                          (if (result (ref $type163))
                           (i64.lt_s
                            (local.tee $10
                             (if (result i64)
                              (ref.test (ref $type69)
                               (local.tee $14
                                (if (result (ref $type68))
                                 (i32.eq
                                  (local.get $1)
                                  (i32.const -1)
                                 )
                                 (then
                                  (global.get $empty69)
                                 )
                                 (else
                                  (if
                                   (i64.gt_u
                                    (local.tee $10
                                     (i64.extend_i32_s
                                      (local.get $1)
                                     )
                                    )
                                    (i64.const 1114111)
                                   )
                                   (then
                                    (unreachable)
                                   )
                                  )
                                  (if
                                   (i32.and
                                    (i64.le_u
                                     (local.get $10)
                                     (i64.const 57343)
                                    )
                                    (i64.ge_u
                                     (local.get $10)
                                     (i64.const 55296)
                                    )
                                   )
                                   (then
                                    (unreachable)
                                   )
                                  )
                                  (struct.new $type70
                                   (i32.wrap_i64
                                    (local.get $10)
                                   )
                                  )
                                 )
                                )
                               )
                              )
                              (then
                               (i64.const -1)
                              )
                              (else
                               (i64.extend_i32_u
                                (struct.get $type70 0
                                 (ref.cast (ref $type70)
                                  (local.get $14)
                                 )
                                )
                               )
                              )
                             )
                            )
                            (i64.const 0)
                           )
                           (then
                            (struct.new $type170
                             (i32.const 6)
                             (global.get $string19)
                            )
                           )
                           (else
                            (drop
                             (ref.as_non_null
                              (global.get $global538)
                             )
                            )
                            (if (result (ref $type163))
                             (i64.eq
                              (local.get $10)
                              (i64.const 40)
                             )
                             (then
                              (struct.new $type168
                               (i32.const 4)
                               (i64.const 1)
                              )
                             )
                             (else
                              (drop
                               (ref.as_non_null
                                (global.get $global538)
                               )
                              )
                              (if (result (ref $type163))
                               (i64.eq
                                (local.get $10)
                                (i64.const 59)
                               )
                               (then
                                (drop
                                 (ref.as_non_null
                                  (global.get $global630)
                                 )
                                )
                                (drop
                                 (ref.as_non_null
                                  (global.get $global525)
                                 )
                                )
                                (if
                                 (i32.eqz
                                  (global.get $ready527)
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
                                (local.set $19
                                 (call $function154
                                  (local.get $0)
                                 )
                                )
                                (if
                                 (i32.eqz
                                  (global.get $ready695)
                                 )
                                 (then
                                  (unreachable)
                                 )
                                )
                                (drop
                                 (ref.as_non_null
                                  (global.get $global695)
                                 )
                                )
                                (if (result (ref $type170))
                                 (i32.eq
                                  (struct.get $type130 0
                                   (local.tee $17
                                    (call $function197
                                     (local.get $0)
                                     (local.get $19)
                                    )
                                   )
                                  )
                                  (i32.const 1)
                                 )
                                 (then
                                  (drop
                                   (ref.cast (ref $type132)
                                    (local.get $17)
                                   )
                                  )
                                  (br $block)
                                 )
                                 (else
                                  (if (result (ref $type170))
                                   (struct.get $type130 0
                                    (local.get $17)
                                   )
                                   (then
                                    (struct.new $type170
                                     (i32.const 6)
                                     (struct.get $type133 1
                                      (ref.cast (ref $type133)
                                       (local.get $17)
                                      )
                                     )
                                    )
                                   )
                                   (else
                                    (struct.new $type170
                                     (i32.const 6)
                                     (global.get $string20)
                                    )
                                   )
                                  )
                                 )
                                )
                               )
                               (else
                                (drop
                                 (ref.as_non_null
                                  (global.get $global538)
                                 )
                                )
                                (if (result (ref $type163))
                                 (i64.eq
                                  (local.get $10)
                                  (i64.const 124)
                                 )
                                 (then
                                  (drop
                                   (ref.as_non_null
                                    (global.get $global635)
                                   )
                                  )
                                  (if (result (ref $type170))
                                   (call $function182
                                    (local.get $0)
                                    (i64.const 1)
                                   )
                                   (then
                                    (drop
                                     (ref.as_non_null
                                      (global.get $global527)
                                     )
                                    )
                                    (return_call $function154
                                     (local.get $0)
                                    )
                                   )
                                   (else
                                    (struct.new $type170
                                     (i32.const 6)
                                     (global.get $string18)
                                    )
                                   )
                                  )
                                 )
                                 (else
                                  (drop
                                   (ref.as_non_null
                                    (global.get $global538)
                                   )
                                  )
                                  (if (result (ref $type163))
                                   (i64.eq
                                    (local.get $10)
                                    (i64.const 92)
                                   )
                                   (then
                                    (if
                                     (i32.eqz
                                      (global.get $ready640)
                                     )
                                     (then
                                      (unreachable)
                                     )
                                    )
                                    (drop
                                     (ref.as_non_null
                                      (global.get $global640)
                                     )
                                    )
                                    (drop
                                     (ref.as_non_null
                                      (global.get $global530)
                                     )
                                    )
                                    (if (result (ref $type163))
                                     (i64.lt_s
                                      (local.tee $10
                                       (call $function155
                                        (local.get $0)
                                       )
                                      )
                                      (i64.const 0)
                                     )
                                     (then
                                      (struct.new $type170
                                       (i32.const 6)
                                       (global.get $string21)
                                      )
                                     )
                                     (else
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global643)
                                       )
                                      )
                                      (if (result (ref $type164))
                                       (call $function184
                                        (local.get $10)
                                       )
                                       (then
                                        (if
                                         (i64.gt_u
                                          (local.get $10)
                                          (i64.const 1114111)
                                         )
                                         (then
                                          (unreachable)
                                         )
                                        )
                                        (if
                                         (i32.and
                                          (i64.le_u
                                           (local.get $10)
                                           (i64.const 57343)
                                          )
                                          (i64.ge_u
                                           (local.get $10)
                                           (i64.const 55296)
                                          )
                                         )
                                         (then
                                          (unreachable)
                                         )
                                        )
                                        (struct.new $type164
                                         (i32.const 0)
                                         (struct.new $type16
                                          (i32.const 2)
                                          (i32.wrap_i64
                                           (local.get $10)
                                          )
                                         )
                                        )
                                       )
                                       (else
                                        (drop
                                         (ref.as_non_null
                                          (global.get $global651)
                                         )
                                        )
                                        (drop
                                         (ref.as_non_null
                                          (global.get $global562)
                                         )
                                        )
                                        (drop
                                         (ref.as_non_null
                                          (global.get $global61)
                                         )
                                        )
                                        (local.set $16
                                         (struct.new $type154
                                          (struct.new $type155
                                           (call $string-new
                                            (i32.const 32)
                                           )
                                          )
                                          (struct.new_default $type156)
                                         )
                                        )
                                        (if
                                         (i64.gt_u
                                          (local.get $10)
                                          (i64.const 1114111)
                                         )
                                         (then
                                          (unreachable)
                                         )
                                        )
                                        (if
                                         (i32.and
                                          (i64.le_u
                                           (local.get $10)
                                           (i64.const 57343)
                                          )
                                          (i64.ge_u
                                           (local.get $10)
                                           (i64.const 55296)
                                          )
                                         )
                                         (then
                                          (unreachable)
                                         )
                                        )
                                        (drop
                                         (ref.as_non_null
                                          (global.get $global611)
                                         )
                                        )
                                        (call $function177
                                         (local.get $16)
                                         (i32.wrap_i64
                                          (local.get $10)
                                         )
                                        )
                                        (local.set $11
                                         (call $function187
                                          (local.get $0)
                                          (local.get $16)
                                          (i32.const 0)
                                          (i32.const 1)
                                         )
                                        )
                                        (if
                                         (i32.eqz
                                          (global.get $ready656)
                                         )
                                         (then
                                          (unreachable)
                                         )
                                        )
                                        (drop
                                         (ref.as_non_null
                                          (global.get $global656)
                                         )
                                        )
                                        (return
                                         (if (result (ref $type163))
                                          (i64.eq
                                           (local.tee $10
                                            (i64.extend_i32_u
                                             (struct.get $type18 1
                                              (local.get $11)
                                             )
                                            )
                                           )
                                           (i64.const 1)
                                          )
                                          (then
                                           (if
                                            (i64.eqz
                                             (local.get $10)
                                            )
                                            (then
                                             (unreachable)
                                            )
                                           )
                                           (struct.new $type164
                                            (i32.const 0)
                                            (struct.new $type16
                                             (i32.const 2)
                                             (array.get $type19
                                              (struct.get $type18 2
                                               (local.get $11)
                                              )
                                              (i32.const 0)
                                             )
                                            )
                                           )
                                          )
                                          (else
                                           (drop
                                            (ref.as_non_null
                                             (global.get $global659)
                                            )
                                           )
                                           (drop
                                            (ref.as_non_null
                                             (global.get $global88)
                                            )
                                           )
                                           (drop
                                            (ref.as_non_null
                                             (global.get $global81)
                                            )
                                           )
                                           (local.set $11
                                            (call $function190
                                             (if (result (ref $type18))
                                              (i64.lt_s
                                               (local.tee $10
                                                (i64.extend_i32_u
                                                 (struct.get $type18 1
                                                  (local.get $11)
                                                 )
                                                )
                                               )
                                               (local.get $10)
                                              )
                                              (then
                                               (unreachable)
                                              )
                                              (else
                                               (drop
                                                (ref.as_non_null
                                                 (global.get $global61)
                                                )
                                               )
                                               (if
                                                (i64.gt_u
                                                 (local.get $10)
                                                 (i64.const 4294967294)
                                                )
                                                (then
                                                 (unreachable)
                                                )
                                               )
                                               (call $string-copy
                                                (local.tee $12
                                                 (call $string-new
                                                  (i32.wrap_i64
                                                   (local.get $10)
                                                  )
                                                 )
                                                )
                                                (i64.const 0)
                                                (local.get $11)
                                                (local.get $10)
                                               )
                                               (local.get $12)
                                              )
                                             )
                                             (i32.const 0)
                                             (i32.const 1)
                                             (i64.const 0)
                                            )
                                           )
                                           (if
                                            (i32.eqz
                                             (global.get $ready665)
                                            )
                                            (then
                                             (unreachable)
                                            )
                                           )
                                           (drop
                                            (ref.as_non_null
                                             (global.get $global665)
                                            )
                                           )
                                           (drop
                                            (ref.as_non_null
                                             (global.get $global103)
                                            )
                                           )
                                           (if (result (ref $type163))
                                            (struct.get $type181 0
                                             (local.tee $18
                                              (if (result (ref $type181))
                                               (if (result i32)
                                                (i64.eq
                                                 (i64.extend_i32_u
                                                  (struct.get $type18 1
                                                   (local.get $11)
                                                  )
                                                 )
                                                 (i64.const 5)
                                                )
                                                (then
                                                 (call $function40
                                                  (local.get $11)
                                                  (global.get $string32)
                                                  (i32.const 0)
                                                  (i32.const 1)
                                                  (i64.const 0)
                                                 )
                                                )
                                                (else
                                                 (i32.const 0)
                                                )
                                               )
                                               (then
                                                (struct.new $type182
                                                 (i32.const 0)
                                                 (i32.const 7)
                                                )
                                               )
                                               (else
                                                (drop
                                                 (ref.as_non_null
                                                  (global.get $global103)
                                                 )
                                                )
                                                (if (result (ref $type181))
                                                 (if (result i32)
                                                  (i64.eq
                                                   (i64.extend_i32_u
                                                    (struct.get $type18 1
                                                     (local.get $11)
                                                    )
                                                   )
                                                   (i64.const 9)
                                                  )
                                                  (then
                                                   (call $function40
                                                    (local.get $11)
                                                    (global.get $string31)
                                                    (i32.const 0)
                                                    (i32.const 1)
                                                    (i64.const 0)
                                                   )
                                                  )
                                                  (else
                                                   (i32.const 0)
                                                  )
                                                 )
                                                 (then
                                                  (struct.new $type182
                                                   (i32.const 0)
                                                   (i32.const 8)
                                                  )
                                                 )
                                                 (else
                                                  (drop
                                                   (ref.as_non_null
                                                    (global.get $global103)
                                                   )
                                                  )
                                                  (if (result (ref $type181))
                                                   (if (result i32)
                                                    (i64.eq
                                                     (i64.extend_i32_u
                                                      (struct.get $type18 1
                                                       (local.get $11)
                                                      )
                                                     )
                                                     (i64.const 6)
                                                    )
                                                    (then
                                                     (call $function40
                                                      (local.get $11)
                                                      (global.get $string30)
                                                      (i32.const 0)
                                                      (i32.const 1)
                                                      (i64.const 0)
                                                     )
                                                    )
                                                    (else
                                                     (i32.const 0)
                                                    )
                                                   )
                                                   (then
                                                    (struct.new $type182
                                                     (i32.const 0)
                                                     (i32.const 127)
                                                    )
                                                   )
                                                   (else
                                                    (drop
                                                     (ref.as_non_null
                                                      (global.get $global103)
                                                     )
                                                    )
                                                    (if (result (ref $type181))
                                                     (if (result i32)
                                                      (i64.eq
                                                       (i64.extend_i32_u
                                                        (struct.get $type18 1
                                                         (local.get $11)
                                                        )
                                                       )
                                                       (i64.const 6)
                                                      )
                                                      (then
                                                       (call $function40
                                                        (local.get $11)
                                                        (global.get $string29)
                                                        (i32.const 0)
                                                        (i32.const 1)
                                                        (i64.const 0)
                                                       )
                                                      )
                                                      (else
                                                       (i32.const 0)
                                                      )
                                                     )
                                                     (then
                                                      (struct.new $type182
                                                       (i32.const 0)
                                                       (i32.const 27)
                                                      )
                                                     )
                                                     (else
                                                      (drop
                                                       (ref.as_non_null
                                                        (global.get $global103)
                                                       )
                                                      )
                                                      (if (result (ref $type181))
                                                       (if (result i32)
                                                        (i64.eq
                                                         (i64.extend_i32_u
                                                          (struct.get $type18 1
                                                           (local.get $11)
                                                          )
                                                         )
                                                         (i64.const 7)
                                                        )
                                                        (then
                                                         (call $function40
                                                          (local.get $11)
                                                          (global.get $string28)
                                                          (i32.const 0)
                                                          (i32.const 1)
                                                          (i64.const 0)
                                                         )
                                                        )
                                                        (else
                                                         (i32.const 0)
                                                        )
                                                       )
                                                       (then
                                                        (struct.new $type182
                                                         (i32.const 0)
                                                         (i32.const 10)
                                                        )
                                                       )
                                                       (else
                                                        (drop
                                                         (ref.as_non_null
                                                          (global.get $global103)
                                                         )
                                                        )
                                                        (if (result (ref $type181))
                                                         (if (result i32)
                                                          (i64.eq
                                                           (i64.extend_i32_u
                                                            (struct.get $type18 1
                                                             (local.get $11)
                                                            )
                                                           )
                                                           (i64.const 4)
                                                          )
                                                          (then
                                                           (call $function40
                                                            (local.get $11)
                                                            (global.get $string27)
                                                            (i32.const 0)
                                                            (i32.const 1)
                                                            (i64.const 0)
                                                           )
                                                          )
                                                          (else
                                                           (i32.const 0)
                                                          )
                                                         )
                                                         (then
                                                          (struct.new_default $type182)
                                                         )
                                                         (else
                                                          (drop
                                                           (ref.as_non_null
                                                            (global.get $global103)
                                                           )
                                                          )
                                                          (if (result (ref $type181))
                                                           (if (result i32)
                                                            (i64.eq
                                                             (i64.extend_i32_u
                                                              (struct.get $type18 1
                                                               (local.get $11)
                                                              )
                                                             )
                                                             (i64.const 6)
                                                            )
                                                            (then
                                                             (call $function40
                                                              (local.get $11)
                                                              (global.get $string26)
                                                              (i32.const 0)
                                                              (i32.const 1)
                                                              (i64.const 0)
                                                             )
                                                            )
                                                            (else
                                                             (i32.const 0)
                                                            )
                                                           )
                                                           (then
                                                            (struct.new $type182
                                                             (i32.const 0)
                                                             (i32.const 13)
                                                            )
                                                           )
                                                           (else
                                                            (drop
                                                             (ref.as_non_null
                                                              (global.get $global103)
                                                             )
                                                            )
                                                            (if (result (ref $type181))
                                                             (if (result i32)
                                                              (i64.eq
                                                               (i64.extend_i32_u
                                                                (struct.get $type18 1
                                                                 (local.get $11)
                                                                )
                                                               )
                                                               (i64.const 5)
                                                              )
                                                              (then
                                                               (call $function40
                                                                (local.get $11)
                                                                (global.get $string25)
                                                                (i32.const 0)
                                                                (i32.const 1)
                                                                (i64.const 0)
                                                               )
                                                              )
                                                              (else
                                                               (i32.const 0)
                                                              )
                                                             )
                                                             (then
                                                              (struct.new $type182
                                                               (i32.const 0)
                                                               (i32.const 32)
                                                              )
                                                             )
                                                             (else
                                                              (drop
                                                               (ref.as_non_null
                                                                (global.get $global103)
                                                               )
                                                              )
                                                              (if (result (ref $type181))
                                                               (if (result i32)
                                                                (i64.eq
                                                                 (i64.extend_i32_u
                                                                  (struct.get $type18 1
                                                                   (local.get $11)
                                                                  )
                                                                 )
                                                                 (i64.const 3)
                                                                )
                                                                (then
                                                                 (call $function40
                                                                  (local.get $11)
                                                                  (global.get $string24)
                                                                  (i32.const 0)
                                                                  (i32.const 1)
                                                                  (i64.const 0)
                                                                 )
                                                                )
                                                                (else
                                                                 (i32.const 0)
                                                                )
                                                               )
                                                               (then
                                                                (struct.new $type182
                                                                 (i32.const 0)
                                                                 (i32.const 9)
                                                                )
                                                               )
                                                               (else
                                                                (if
                                                                 (i64.eqz
                                                                  (i64.extend_i32_u
                                                                   (struct.get $type18 1
                                                                    (local.get $11)
                                                                   )
                                                                  )
                                                                 )
                                                                 (then
                                                                  (unreachable)
                                                                 )
                                                                )
                                                                (if (result (ref $type181))
                                                                 (i32.eq
                                                                  (array.get $type19
                                                                   (struct.get $type18 2
                                                                    (local.get $11)
                                                                   )
                                                                   (i32.const 0)
                                                                  )
                                                                  (i32.const 120)
                                                                 )
                                                                 (then
                                                                  (drop
                                                                   (ref.as_non_null
                                                                    (global.get $global667)
                                                                   )
                                                                  )
                                                                  (call $function193
                                                                   (local.get $11)
                                                                   (i32.const 0)
                                                                   (i32.const 1)
                                                                   (i64.const 1)
                                                                   (i64.const 0)
                                                                  )
                                                                 )
                                                                 (else
                                                                  (struct.new $type184
                                                                   (i32.const 2)
                                                                   (global.get $string23)
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
                                            (then
                                             (if (result (ref $type170))
                                              (i32.eq
                                               (struct.get $type181 0
                                                (local.get $18)
                                               )
                                               (i32.const 2)
                                              )
                                              (then
                                               (struct.new $type170
                                                (i32.const 6)
                                                (struct.get $type184 1
                                                 (ref.cast (ref $type184)
                                                  (local.get $18)
                                                 )
                                                )
                                               )
                                              )
                                              (else
                                               (unreachable)
                                              )
                                             )
                                            )
                                            (else
                                             (struct.new $type164
                                              (i32.const 0)
                                              (struct.new $type16
                                               (i32.const 2)
                                               (struct.get $type182 1
                                                (ref.cast (ref $type182)
                                                 (local.get $18)
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
                                    (drop
                                     (ref.as_non_null
                                      (global.get $global538)
                                     )
                                    )
                                    (if (result (ref $type163))
                                     (if (result i32)
                                      (local.tee $1
                                       (i64.eq
                                        (local.get $10)
                                        (i64.const 117)
                                       )
                                      )
                                      (then
                                       (local.get $1)
                                      )
                                      (else
                                       (drop
                                        (ref.as_non_null
                                         (global.get $global538)
                                        )
                                       )
                                       (i64.eq
                                        (local.get $10)
                                        (i64.const 85)
                                       )
                                      )
                                     )
                                     (then
                                      (if
                                       (i32.eqz
                                        (global.get $ready677)
                                       )
                                       (then
                                        (unreachable)
                                       )
                                      )
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global677)
                                       )
                                      )
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global549)
                                       )
                                      )
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global552)
                                       )
                                      )
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global137)
                                       )
                                      )
                                      (local.set $1
                                       (call $snail:io/peek-character
                                        (struct.get $type56 0
                                         (struct.get $type58 0
                                          (local.get $0)
                                         )
                                        )
                                       )
                                      )
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global133)
                                       )
                                      )
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global532)
                                       )
                                      )
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global538)
                                       )
                                      )
                                      (if (result (ref $type163))
                                       (if (result i32)
                                        (if (result i32)
                                         (i64.eq
                                          (if (result i64)
                                           (ref.test (ref $type69)
                                            (local.tee $14
                                             (if (result (ref $type68))
                                              (i32.eq
                                               (local.get $1)
                                               (i32.const -1)
                                              )
                                              (then
                                               (global.get $empty69)
                                              )
                                              (else
                                               (if
                                                (i64.gt_u
                                                 (local.tee $10
                                                  (i64.extend_i32_s
                                                   (local.get $1)
                                                  )
                                                 )
                                                 (i64.const 1114111)
                                                )
                                                (then
                                                 (unreachable)
                                                )
                                               )
                                               (if
                                                (i32.and
                                                 (i64.le_u
                                                  (local.get $10)
                                                  (i64.const 57343)
                                                 )
                                                 (i64.ge_u
                                                  (local.get $10)
                                                  (i64.const 55296)
                                                 )
                                                )
                                                (then
                                                 (unreachable)
                                                )
                                               )
                                               (struct.new $type70
                                                (i32.wrap_i64
                                                 (local.get $10)
                                                )
                                               )
                                              )
                                             )
                                            )
                                           )
                                           (then
                                            (i64.const -1)
                                           )
                                           (else
                                            (i64.extend_i32_u
                                             (struct.get $type70 0
                                              (ref.cast (ref $type70)
                                               (local.get $14)
                                              )
                                             )
                                            )
                                           )
                                          )
                                          (i64.const 56)
                                         )
                                         (then
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global135)
                                           )
                                          )
                                          (local.set $1
                                           (call $snail:io/read-character
                                            (struct.get $type56 0
                                             (struct.get $type58 0
                                              (local.get $0)
                                             )
                                            )
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global133)
                                           )
                                          )
                                          (drop
                                           (if (result (ref $type68))
                                            (i32.eq
                                             (local.get $1)
                                             (i32.const -1)
                                            )
                                            (then
                                             (global.get $empty69)
                                            )
                                            (else
                                             (if
                                              (i64.gt_u
                                               (local.tee $10
                                                (i64.extend_i32_s
                                                 (local.get $1)
                                                )
                                               )
                                               (i64.const 1114111)
                                              )
                                              (then
                                               (unreachable)
                                              )
                                             )
                                             (if
                                              (i32.and
                                               (i64.le_u
                                                (local.get $10)
                                                (i64.const 57343)
                                               )
                                               (i64.ge_u
                                                (local.get $10)
                                                (i64.const 55296)
                                               )
                                              )
                                              (then
                                               (unreachable)
                                              )
                                             )
                                             (struct.new $type70
                                              (i32.wrap_i64
                                               (local.get $10)
                                              )
                                             )
                                            )
                                           )
                                          )
                                          (i32.const 1)
                                         )
                                         (else
                                          (i32.const 0)
                                         )
                                        )
                                        (then
                                         (drop
                                          (ref.as_non_null
                                           (global.get $global549)
                                          )
                                         )
                                         (drop
                                          (ref.as_non_null
                                           (global.get $global552)
                                          )
                                         )
                                         (drop
                                          (ref.as_non_null
                                           (global.get $global137)
                                          )
                                         )
                                         (local.set $1
                                          (call $snail:io/peek-character
                                           (struct.get $type56 0
                                            (struct.get $type58 0
                                             (local.get $0)
                                            )
                                           )
                                          )
                                         )
                                         (drop
                                          (ref.as_non_null
                                           (global.get $global133)
                                          )
                                         )
                                         (drop
                                          (ref.as_non_null
                                           (global.get $global532)
                                          )
                                         )
                                         (drop
                                          (ref.as_non_null
                                           (global.get $global538)
                                          )
                                         )
                                         (if (result i32)
                                          (i64.eq
                                           (if (result i64)
                                            (ref.test (ref $type69)
                                             (local.tee $14
                                              (if (result (ref $type68))
                                               (i32.eq
                                                (local.get $1)
                                                (i32.const -1)
                                               )
                                               (then
                                                (global.get $empty69)
                                               )
                                               (else
                                                (if
                                                 (i64.gt_u
                                                  (local.tee $10
                                                   (i64.extend_i32_s
                                                    (local.get $1)
                                                   )
                                                  )
                                                  (i64.const 1114111)
                                                 )
                                                 (then
                                                  (unreachable)
                                                 )
                                                )
                                                (if
                                                 (i32.and
                                                  (i64.le_u
                                                   (local.get $10)
                                                   (i64.const 57343)
                                                  )
                                                  (i64.ge_u
                                                   (local.get $10)
                                                   (i64.const 55296)
                                                  )
                                                 )
                                                 (then
                                                  (unreachable)
                                                 )
                                                )
                                                (struct.new $type70
                                                 (i32.wrap_i64
                                                  (local.get $10)
                                                 )
                                                )
                                               )
                                              )
                                             )
                                            )
                                            (then
                                             (i64.const -1)
                                            )
                                            (else
                                             (i64.extend_i32_u
                                              (struct.get $type70 0
                                               (ref.cast (ref $type70)
                                                (local.get $14)
                                               )
                                              )
                                             )
                                            )
                                           )
                                           (i64.const 40)
                                          )
                                          (then
                                           (drop
                                            (ref.as_non_null
                                             (global.get $global135)
                                            )
                                           )
                                           (local.set $1
                                            (call $snail:io/read-character
                                             (struct.get $type56 0
                                              (struct.get $type58 0
                                               (local.get $0)
                                              )
                                             )
                                            )
                                           )
                                           (drop
                                            (ref.as_non_null
                                             (global.get $global133)
                                            )
                                           )
                                           (drop
                                            (if (result (ref $type68))
                                             (i32.eq
                                              (local.get $1)
                                              (i32.const -1)
                                             )
                                             (then
                                              (global.get $empty69)
                                             )
                                             (else
                                              (if
                                               (i64.gt_u
                                                (local.tee $10
                                                 (i64.extend_i32_s
                                                  (local.get $1)
                                                 )
                                                )
                                                (i64.const 1114111)
                                               )
                                               (then
                                                (unreachable)
                                               )
                                              )
                                              (if
                                               (i32.and
                                                (i64.le_u
                                                 (local.get $10)
                                                 (i64.const 57343)
                                                )
                                                (i64.ge_u
                                                 (local.get $10)
                                                 (i64.const 55296)
                                                )
                                               )
                                               (then
                                                (unreachable)
                                               )
                                              )
                                              (struct.new $type70
                                               (i32.wrap_i64
                                                (local.get $10)
                                               )
                                              )
                                             )
                                            )
                                           )
                                           (i32.const 1)
                                          )
                                          (else
                                           (i32.const 0)
                                          )
                                         )
                                        )
                                        (else
                                         (i32.const 0)
                                        )
                                       )
                                       (then
                                        (struct.new $type168
                                         (i32.const 4)
                                         (i64.const 2)
                                        )
                                       )
                                       (else
                                        (struct.new $type170
                                         (i32.const 6)
                                         (global.get $string34)
                                        )
                                       )
                                      )
                                     )
                                     (else
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global538)
                                       )
                                      )
                                      (if (result (ref $type163))
                                       (i64.eq
                                        (local.get $10)
                                        (i64.const 33)
                                       )
                                       (then
                                        (struct.new $type170
                                         (i32.const 6)
                                         (global.get $string17)
                                        )
                                       )
                                       (else
                                        (if (result (ref $type163))
                                         (i32.and
                                          (i64.le_s
                                           (local.get $10)
                                           (i64.const 57)
                                          )
                                          (i64.ge_s
                                           (local.get $10)
                                           (i64.const 48)
                                          )
                                         )
                                         (then
                                          (struct.new $type170
                                           (i32.const 6)
                                           (global.get $string16)
                                          )
                                         )
                                         (else
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global651)
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global562)
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global61)
                                           )
                                          )
                                          (local.set $16
                                           (struct.new $type154
                                            (struct.new $type155
                                             (call $string-new
                                              (i32.const 32)
                                             )
                                            )
                                            (struct.new_default $type156)
                                           )
                                          )
                                          (if
                                           (i64.gt_u
                                            (local.get $10)
                                            (i64.const 1114111)
                                           )
                                           (then
                                            (unreachable)
                                           )
                                          )
                                          (if
                                           (i32.and
                                            (i64.le_u
                                             (local.get $10)
                                             (i64.const 57343)
                                            )
                                            (i64.ge_u
                                             (local.get $10)
                                             (i64.const 55296)
                                            )
                                           )
                                           (then
                                            (unreachable)
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global611)
                                           )
                                          )
                                          (call $function177
                                           (local.get $16)
                                           (i32.wrap_i64
                                            (local.get $10)
                                           )
                                          )
                                          (local.set $11
                                           (call $function187
                                            (local.get $0)
                                            (local.get $16)
                                            (i32.const 0)
                                            (i32.const 1)
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global90)
                                           )
                                          )
                                          (local.set $13
                                           (call $function35
                                            (struct.new $type48
                                             (global.get $string15)
                                             (struct.new $type48
                                              (local.get $11)
                                              (ref.null none)
                                             )
                                            )
                                           )
                                          )
                                          (if
                                           (i32.eqz
                                            (global.get $ready679)
                                           )
                                           (then
                                            (unreachable)
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global679)
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global659)
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global88)
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global81)
                                           )
                                          )
                                          (local.set $11
                                           (call $function190
                                            (if (result (ref $type18))
                                             (i64.lt_s
                                              (local.tee $10
                                               (i64.extend_i32_u
                                                (struct.get $type18 1
                                                 (local.get $13)
                                                )
                                               )
                                              )
                                              (local.get $10)
                                             )
                                             (then
                                              (unreachable)
                                             )
                                             (else
                                              (drop
                                               (ref.as_non_null
                                                (global.get $global61)
                                               )
                                              )
                                              (if
                                               (i64.gt_u
                                                (local.get $10)
                                                (i64.const 4294967294)
                                               )
                                               (then
                                                (unreachable)
                                               )
                                              )
                                              (call $string-copy
                                               (local.tee $12
                                                (call $string-new
                                                 (i32.wrap_i64
                                                  (local.get $10)
                                                 )
                                                )
                                               )
                                               (i64.const 0)
                                               (local.get $13)
                                               (local.get $10)
                                              )
                                              (local.get $12)
                                             )
                                            )
                                            (i32.const 0)
                                            (i32.const 1)
                                            (i64.const 0)
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global103)
                                           )
                                          )
                                          (if (result (ref $type163))
                                           (if (result i32)
                                            (local.tee $1
                                             (if (result i32)
                                              (i64.eq
                                               (i64.extend_i32_u
                                                (struct.get $type18 1
                                                 (local.get $11)
                                                )
                                               )
                                               (i64.const 2)
                                              )
                                              (then
                                               (call $function40
                                                (local.get $11)
                                                (global.get $string38)
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
                                            (then
                                             (local.get $1)
                                            )
                                            (else
                                             (drop
                                              (ref.as_non_null
                                               (global.get $global103)
                                              )
                                             )
                                             (if (result i32)
                                              (i64.eq
                                               (i64.extend_i32_u
                                                (struct.get $type18 1
                                                 (local.get $11)
                                                )
                                               )
                                               (i64.const 5)
                                              )
                                              (then
                                               (call $function40
                                                (local.get $11)
                                                (global.get $string39)
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
                                           (then
                                            (struct.new $type164
                                             (i32.const 0)
                                             (struct.new $type15
                                              (i32.const 1)
                                              (i32.const 1)
                                             )
                                            )
                                           )
                                           (else
                                            (drop
                                             (ref.as_non_null
                                              (global.get $global103)
                                             )
                                            )
                                            (if (result (ref $type163))
                                             (if (result i32)
                                              (local.tee $1
                                               (if (result i32)
                                                (i64.eq
                                                 (i64.extend_i32_u
                                                  (struct.get $type18 1
                                                   (local.get $11)
                                                  )
                                                 )
                                                 (i64.const 2)
                                                )
                                                (then
                                                 (call $function40
                                                  (local.get $11)
                                                  (global.get $string36)
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
                                              (then
                                               (local.get $1)
                                              )
                                              (else
                                               (drop
                                                (ref.as_non_null
                                                 (global.get $global103)
                                                )
                                               )
                                               (if (result i32)
                                                (i64.eq
                                                 (i64.extend_i32_u
                                                  (struct.get $type18 1
                                                   (local.get $11)
                                                  )
                                                 )
                                                 (i64.const 6)
                                                )
                                                (then
                                                 (call $function40
                                                  (local.get $11)
                                                  (global.get $string37)
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
                                             (then
                                              (struct.new $type164
                                               (i32.const 0)
                                               (struct.new $type15
                                                (i32.const 1)
                                                (i32.const 0)
                                               )
                                              )
                                             )
                                             (else
                                              (drop
                                               (ref.as_non_null
                                                (global.get $global379)
                                               )
                                              )
                                              (drop
                                               (ref.as_non_null
                                                (global.get $global317)
                                               )
                                              )
                                              (local.set $1
                                               (call $snail:datum/token-parse
                                                (local.tee $2
                                                 (call $function104
                                                  (local.get $13)
                                                 )
                                                )
                                               )
                                              )
                                              (drop
                                               (ref.as_non_null
                                                (global.get $global376)
                                               )
                                              )
                                              (local.set $15
                                               (call $function121
                                                (local.get $2)
                                                (local.get $1)
                                               )
                                              )
                                              (call $snail:datum/token-close
                                               (local.get $2)
                                              )
                                              (if (result (ref $type163))
                                               (i32.eq
                                                (struct.get $type121 0
                                                 (local.get $15)
                                                )
                                                (i32.const 1)
                                               )
                                               (then
                                                (struct.new $type164
                                                 (i32.const 0)
                                                 (struct.new $type23
                                                  (i32.const 5)
                                                  (struct.get $type123 1
                                                   (ref.cast (ref $type123)
                                                    (local.get $15)
                                                   )
                                                  )
                                                 )
                                                )
                                               )
                                               (else
                                                (if (result (ref $type170))
                                                 (i32.eq
                                                  (struct.get $type121 0
                                                   (local.get $15)
                                                  )
                                                  (i32.const 2)
                                                 )
                                                 (then
                                                  (struct.new $type170
                                                   (i32.const 6)
                                                   (struct.get $type124 1
                                                    (ref.cast (ref $type124)
                                                     (local.get $15)
                                                    )
                                                   )
                                                  )
                                                 )
                                                 (else
                                                  (struct.new $type170
                                                   (i32.const 6)
                                                   (global.get $string35)
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
                        (else
                         (drop
                          (ref.as_non_null
                           (global.get $global538)
                          )
                         )
                         (if (result (ref $type170))
                          (if (result i32)
                           (local.tee $1
                            (i64.eq
                             (local.get $10)
                             (i64.const 91)
                            )
                           )
                           (then
                            (local.get $1)
                           )
                           (else
                            (drop
                             (ref.as_non_null
                              (global.get $global538)
                             )
                            )
                            (if (result i32)
                             (local.tee $1
                              (i64.eq
                               (local.get $10)
                               (i64.const 93)
                              )
                             )
                             (then
                              (local.get $1)
                             )
                             (else
                              (drop
                               (ref.as_non_null
                                (global.get $global538)
                               )
                              )
                              (if (result i32)
                               (local.tee $1
                                (i64.eq
                                 (local.get $10)
                                 (i64.const 123)
                                )
                               )
                               (then
                                (local.get $1)
                               )
                               (else
                                (drop
                                 (ref.as_non_null
                                  (global.get $global538)
                                 )
                                )
                                (i64.eq
                                 (local.get $10)
                                 (i64.const 125)
                                )
                               )
                              )
                             )
                            )
                           )
                          )
                          (then
                           (struct.new $type170
                            (i32.const 6)
                            (global.get $string4)
                           )
                          )
                          (else
                           (drop
                            (ref.as_non_null
                             (global.get $global651)
                            )
                           )
                           (drop
                            (ref.as_non_null
                             (global.get $global562)
                            )
                           )
                           (drop
                            (ref.as_non_null
                             (global.get $global61)
                            )
                           )
                           (local.set $16
                            (struct.new $type154
                             (struct.new $type155
                              (call $string-new
                               (i32.const 32)
                              )
                             )
                             (struct.new_default $type156)
                            )
                           )
                           (if
                            (i64.gt_u
                             (local.get $10)
                             (i64.const 1114111)
                            )
                            (then
                             (unreachable)
                            )
                           )
                           (if
                            (i32.and
                             (i64.le_u
                              (local.get $10)
                              (i64.const 57343)
                             )
                             (i64.ge_u
                              (local.get $10)
                              (i64.const 55296)
                             )
                            )
                            (then
                             (unreachable)
                            )
                           )
                           (drop
                            (ref.as_non_null
                             (global.get $global611)
                            )
                           )
                           (call $function177
                            (local.get $16)
                            (i32.wrap_i64
                             (local.get $10)
                            )
                           )
                           (local.set $11
                            (call $function187
                             (local.get $0)
                             (local.get $16)
                             (i32.const 0)
                             (i32.const 1)
                            )
                           )
                           (if
                            (i32.eqz
                             (global.get $ready690)
                            )
                            (then
                             (unreachable)
                            )
                           )
                           (drop
                            (ref.as_non_null
                             (global.get $global690)
                            )
                           )
                           (drop
                            (ref.as_non_null
                             (global.get $global103)
                            )
                           )
                           (return
                            (if (result (ref $type163))
                             (if (result i32)
                              (i64.eq
                               (i64.extend_i32_u
                                (struct.get $type18 1
                                 (local.get $11)
                                )
                               )
                               (i64.const 1)
                              )
                              (then
                               (call $function40
                                (local.get $11)
                                (global.get $string40)
                                (i32.const 0)
                                (i32.const 1)
                                (i64.const 0)
                               )
                              )
                              (else
                               (i32.const 0)
                              )
                             )
                             (then
                              (global.get $empty167)
                             )
                             (else
                              (drop
                               (ref.as_non_null
                                (global.get $global418)
                               )
                              )
                              (drop
                               (ref.as_non_null
                                (global.get $global317)
                               )
                              )
                              (if (result (ref $type163))
                               (i32.eq
                                (struct.get $type130 0
                                 (local.tee $17
                                  (if (result (ref $type130))
                                   (local.tee $1
                                    (call $snail:datum/token-parse
                                     (local.tee $7
                                      (call $function104
                                       (local.get $11)
                                      )
                                     )
                                    )
                                   )
                                   (then
                                    (drop
                                     (ref.as_non_null
                                      (global.get $global411)
                                     )
                                    )
                                    (drop
                                     (ref.as_non_null
                                      (global.get $global376)
                                     )
                                    )
                                    (local.set $15
                                     (call $function121
                                      (local.get $7)
                                      (local.get $1)
                                     )
                                    )
                                    (call $snail:datum/token-close
                                     (local.get $7)
                                    )
                                    (if (result (ref $type130))
                                     (i32.eq
                                      (struct.get $type121 0
                                       (local.get $15)
                                      )
                                      (i32.const 1)
                                     )
                                     (then
                                      (struct.new $type132
                                       (i32.const 1)
                                       (struct.new $type23
                                        (i32.const 5)
                                        (struct.get $type123 1
                                         (ref.cast (ref $type123)
                                          (local.get $15)
                                         )
                                        )
                                       )
                                      )
                                     )
                                     (else
                                      (if (result (ref $type133))
                                       (i32.eq
                                        (struct.get $type121 0
                                         (local.get $15)
                                        )
                                        (i32.const 2)
                                       )
                                       (then
                                        (struct.new $type133
                                         (i32.const 2)
                                         (struct.get $type124 1
                                          (ref.cast (ref $type124)
                                           (local.get $15)
                                          )
                                         )
                                        )
                                       )
                                       (else
                                        (unreachable)
                                       )
                                      )
                                     )
                                    )
                                   )
                                   (else
                                    (if (result (ref $type130))
                                     (i32.eq
                                      (block $block24 (result i32)
                                       (if
                                        (i32.ne
                                         (local.tee $1
                                          (i32.load8_u
                                           (i32.const 1138012)
                                          )
                                         )
                                         (i32.const 1)
                                        )
                                        (then
                                         (block $block3
                                          (block $block1
                                           (block $block2
                                            (br_table $block1 $block2 $block3
                                             (i32.sub
                                              (local.get $1)
                                              (i32.const 1)
                                             )
                                            )
                                           )
                                           (call $_RNvNtCsdHhIpgkcIfN_4core9panicking9panic_fmt
                                            (i32.const 1061072)
                                            (i32.const 125)
                                            (i32.const 1061136)
                                           )
                                           (unreachable)
                                          )
                                          (i32.store8
                                           (i32.const 1138012)
                                           (i32.const 2)
                                          )
                                          (call $_ZN4core3ptr109drop_in_place$LT$alloc..collections..btree..map..BTreeMap$LT$u32$C$snail_runtime..strict_datum..Token$GT$$GT$17h82df8614fee55166E
                                           (i32.const 1138000)
                                          )
                                         )
                                         (i32.store8
                                          (i32.const 1138012)
                                          (i32.const 1)
                                         )
                                         (i64.store align=4
                                          (i32.const 1137992)
                                          (i64.const 0)
                                         )
                                         (i32.store
                                          (i32.const 1138008)
                                          (i32.const 0)
                                         )
                                         (i32.store
                                          (i32.const 1138000)
                                          (i32.const 0)
                                         )
                                        )
                                       )
                                       (block $block7
                                        (if
                                         (i32.lt_u
                                          (local.tee $4
                                           (i32.load
                                            (i32.const 1137992)
                                           )
                                          )
                                          (i32.const 2147483647)
                                         )
                                         (then
                                          (i32.store
                                           (i32.const 1137992)
                                           (i32.add
                                            (local.get $4)
                                            (i32.const 1)
                                           )
                                          )
                                          (block $block6
                                           (block $block4
                                            (br_if $block4
                                             (i32.eqz
                                              (local.tee $6
                                               (i32.load
                                                (i32.const 1138000)
                                               )
                                              )
                                             )
                                            )
                                            (local.set $8
                                             (i32.load
                                              (i32.const 1138004)
                                             )
                                            )
                                            (loop $label1
                                             (local.set $9
                                              (i32.add
                                               (local.get $6)
                                               (i32.const 532)
                                              )
                                             )
                                             (local.set $5
                                              (i32.shl
                                               (local.tee $1
                                                (i32.load16_u offset=578
                                                 (local.get $6)
                                                )
                                               )
                                               (i32.const 2)
                                              )
                                             )
                                             (local.set $2
                                              (i32.const -1)
                                             )
                                             (block $block5
                                              (loop $label
                                               (if
                                                (i32.eqz
                                                 (local.get $5)
                                                )
                                                (then
                                                 (local.set $2
                                                  (local.get $1)
                                                 )
                                                 (br $block5)
                                                )
                                               )
                                               (local.set $3
                                                (i32.load
                                                 (local.get $9)
                                                )
                                               )
                                               (local.set $5
                                                (i32.sub
                                                 (local.get $5)
                                                 (i32.const 4)
                                                )
                                               )
                                               (local.set $2
                                                (i32.add
                                                 (local.get $2)
                                                 (i32.const 1)
                                                )
                                               )
                                               (local.set $9
                                                (i32.add
                                                 (local.get $9)
                                                 (i32.const 4)
                                                )
                                               )
                                               (br_if $label
                                                (i32.eq
                                                 (local.tee $3
                                                  (i32.and
                                                   (i32.sub
                                                    (i32.lt_u
                                                     (local.get $3)
                                                     (local.get $7)
                                                    )
                                                    (i32.gt_u
                                                     (local.get $3)
                                                     (local.get $7)
                                                    )
                                                   )
                                                   (i32.const 255)
                                                  )
                                                 )
                                                 (i32.const 1)
                                                )
                                               )
                                              )
                                              (br_if $block6
                                               (i32.eqz
                                                (local.get $3)
                                               )
                                              )
                                             )
                                             (br_if $block4
                                              (i32.eqz
                                               (local.get $8)
                                              )
                                             )
                                             (local.set $8
                                              (i32.sub
                                               (local.get $8)
                                               (i32.const 1)
                                              )
                                             )
                                             (local.set $6
                                              (i32.load offset=584
                                               (i32.add
                                                (local.get $6)
                                                (i32.shl
                                                 (local.get $2)
                                                 (i32.const 2)
                                                )
                                               )
                                              )
                                             )
                                             (br $label1)
                                            )
                                            (unreachable)
                                           )
                                           (br_if $block7
                                            (i32.eqz
                                             (local.tee $3
                                              (call $dlmalloc
                                               (i32.const 30)
                                              )
                                             )
                                            )
                                           )
                                           (i32.store
                                            (i32.const 1137992)
                                            (local.get $4)
                                           )
                                           (i64.store offset=22 align=1
                                            (local.get $3)
                                            (i64.load align=1
                                             (i32.const 1055937)
                                            )
                                           )
                                           (i64.store offset=16 align=1
                                            (local.get $3)
                                            (i64.load align=1
                                             (i32.const 1055931)
                                            )
                                           )
                                           (i64.store offset=8 align=1
                                            (local.get $3)
                                            (i64.load align=1
                                             (i32.const 1055923)
                                            )
                                           )
                                           (i64.store align=1
                                            (local.get $3)
                                            (i64.load align=1
                                             (i32.const 1055915)
                                            )
                                           )
                                           (global.set $__stack_pointer
                                            (local.tee $1
                                             (i32.sub
                                              (global.get $__stack_pointer)
                                              (i32.const 16)
                                             )
                                            )
                                           )
                                           (call $_ZN13snail_runtime9strict_io11release_all17h60f1fb813a72b702E
                                            (i32.add
                                             (local.get $1)
                                             (i32.const 4)
                                            )
                                           )
                                           (if
                                            (i32.gt_s
                                             (i32.load offset=4
                                              (local.get $1)
                                             )
                                             (i32.const 0)
                                            )
                                            (then
                                             (call $dlfree
                                              (i32.load offset=8
                                               (local.get $1)
                                              )
                                             )
                                            )
                                           )
                                           (global.set $__stack_pointer
                                            (i32.add
                                             (local.get $1)
                                             (i32.const 16)
                                            )
                                           )
                                           (global.set $__stack_pointer
                                            (local.tee $2
                                             (i32.sub
                                              (global.get $__stack_pointer)
                                              (i32.const 32)
                                             )
                                            )
                                           )
                                           (call $_RNvMNtCsi9YzqDQQz2q_5alloc6stringNtB2_6String15from_utf8_lossy
                                            (local.tee $1
                                             (i32.add
                                              (local.get $2)
                                              (i32.const 12)
                                             )
                                            )
                                            (local.get $3)
                                            (i32.const 30)
                                           )
                                           (i64.store offset=24
                                            (local.get $2)
                                            (i64.or
                                             (i64.extend_i32_u
                                              (local.get $1)
                                             )
                                             (i64.const 103079215104)
                                            )
                                           )
                                           (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio7__eprint
                                            (i32.add
                                             (local.get $2)
                                             (i32.const 24)
                                            )
                                           )
                                           (local.set $1
                                            (i32.load offset=16
                                             (local.get $2)
                                            )
                                           )
                                           (if
                                            (i32.gt_s
                                             (i32.load offset=12
                                              (local.get $2)
                                             )
                                             (i32.const 0)
                                            )
                                            (then
                                             (call $dlfree
                                              (local.get $1)
                                             )
                                            )
                                           )
                                           (call $_RNvNtCset5xJoy1xWQ_3std7process4exit)
                                           (unreachable)
                                          )
                                          (br $block24
                                           (block (result i32)
                                            (local.set $scratch
                                             (block $block14 (result i32)
                                              (local.set $5
                                               (i32.load offset=4
                                                (local.tee $1
                                                 (i32.add
                                                  (local.tee $1
                                                   (i32.add
                                                    (local.get $6)
                                                    (i32.mul
                                                     (local.get $2)
                                                     (i32.const 48)
                                                    )
                                                   )
                                                  )
                                                  (select
                                                   (i32.const 8)
                                                   (i32.const 32)
                                                   (i64.eq
                                                    (i64.load
                                                     (local.get $1)
                                                    )
                                                    (i64.const 6)
                                                   )
                                                  )
                                                 )
                                                )
                                               )
                                              )
                                              (block $block22
                                               (block $block8
                                                (br_if $block8
                                                 (i32.eqz
                                                  (local.tee $1
                                                   (i32.load offset=8
                                                    (local.get $1)
                                                   )
                                                  )
                                                 )
                                                )
                                                (local.set $2
                                                 (block $block9 (result i32)
                                                  (if
                                                   (i32.ge_s
                                                    (local.tee $4
                                                     (i32.load8_s
                                                      (local.get $5)
                                                     )
                                                    )
                                                    (i32.const 0)
                                                   )
                                                   (then
                                                    (local.set $6
                                                     (i32.and
                                                      (local.get $4)
                                                      (i32.const 255)
                                                     )
                                                    )
                                                    (br $block9
                                                     (i32.add
                                                      (local.get $5)
                                                      (i32.const 1)
                                                     )
                                                    )
                                                   )
                                                  )
                                                  (local.set $2
                                                   (i32.and
                                                    (i32.load8_u offset=1
                                                     (local.get $5)
                                                    )
                                                    (i32.const 63)
                                                   )
                                                  )
                                                  (local.set $3
                                                   (i32.and
                                                    (local.get $4)
                                                    (i32.const 31)
                                                   )
                                                  )
                                                  (if
                                                   (i32.le_u
                                                    (local.get $4)
                                                    (i32.const -33)
                                                   )
                                                   (then
                                                    (local.set $6
                                                     (i32.or
                                                      (i32.shl
                                                       (local.get $3)
                                                       (i32.const 6)
                                                      )
                                                      (local.get $2)
                                                     )
                                                    )
                                                    (br $block9
                                                     (i32.add
                                                      (local.get $5)
                                                      (i32.const 2)
                                                     )
                                                    )
                                                   )
                                                  )
                                                  (local.set $2
                                                   (i32.or
                                                    (i32.and
                                                     (i32.load8_u offset=2
                                                      (local.get $5)
                                                     )
                                                     (i32.const 63)
                                                    )
                                                    (i32.shl
                                                     (local.get $2)
                                                     (i32.const 6)
                                                    )
                                                   )
                                                  )
                                                  (if
                                                   (i32.lt_u
                                                    (local.get $4)
                                                    (i32.const -16)
                                                   )
                                                   (then
                                                    (local.set $6
                                                     (i32.or
                                                      (local.get $2)
                                                      (i32.shl
                                                       (local.get $3)
                                                       (i32.const 12)
                                                      )
                                                     )
                                                    )
                                                    (br $block9
                                                     (i32.add
                                                      (local.get $5)
                                                      (i32.const 3)
                                                     )
                                                    )
                                                   )
                                                  )
                                                  (local.set $6
                                                   (i32.or
                                                    (i32.and
                                                     (i32.shl
                                                      (local.get $3)
                                                      (i32.const 18)
                                                     )
                                                     (i32.const 1835008)
                                                    )
                                                    (i32.or
                                                     (i32.and
                                                      (i32.load8_u offset=3
                                                       (local.get $5)
                                                      )
                                                      (i32.const 63)
                                                     )
                                                     (i32.shl
                                                      (local.get $2)
                                                      (i32.const 6)
                                                     )
                                                    )
                                                   )
                                                  )
                                                  (i32.add
                                                   (local.get $5)
                                                   (i32.const 4)
                                                  )
                                                 )
                                                )
                                                (local.set $5
                                                 (i32.add
                                                  (local.get $1)
                                                  (local.get $5)
                                                 )
                                                )
                                                (block $block13
                                                 (local.set $2
                                                  (block $block17 (result i32)
                                                   (block $block18
                                                    (local.set $2
                                                     (block $block15 (result i32)
                                                      (block $block16
                                                       (block $block12
                                                        (block $block10
                                                         (block $block11
                                                          (br_table $block10 $block11 $block10 $block12 $block11
                                                           (i32.sub
                                                            (local.get $6)
                                                            (i32.const 43)
                                                           )
                                                          )
                                                         )
                                                         (br_if $block13
                                                          (i32.lt_u
                                                           (i32.sub
                                                            (i32.and
                                                             (local.get $6)
                                                             (i32.const 2097119)
                                                            )
                                                            (i32.const 65)
                                                           )
                                                           (i32.const 26)
                                                          )
                                                         )
                                                         (if
                                                          (i32.ge_u
                                                           (local.get $6)
                                                           (i32.const 170)
                                                          )
                                                          (then
                                                           (br_if $block13
                                                            (call $_RNvNtNtNtCsdHhIpgkcIfN_4core7unicode12unicode_data10alphabetic11lookup_slow
                                                             (local.get $6)
                                                            )
                                                           )
                                                          )
                                                         )
                                                         (br_if $block13
                                                          (call $_RNvXs2_NtNtCsdHhIpgkcIfN_4core3str7patterncNtB5_7Pattern15is_contained_in
                                                           (local.get $6)
                                                           (i32.const 1057340)
                                                           (i32.const 15)
                                                          )
                                                         )
                                                         (br $block8)
                                                        )
                                                        (drop
                                                         (br_if $block14
                                                          (i32.const 1)
                                                          (i32.eq
                                                           (local.get $2)
                                                           (local.get $5)
                                                          )
                                                         )
                                                        )
                                                        (if
                                                         (i32.ge_s
                                                          (local.tee $4
                                                           (i32.load8_s
                                                            (local.get $2)
                                                           )
                                                          )
                                                          (i32.const 0)
                                                         )
                                                         (then
                                                          (local.set $1
                                                           (i32.and
                                                            (local.get $4)
                                                            (i32.const 255)
                                                           )
                                                          )
                                                          (br $block15
                                                           (i32.add
                                                            (local.get $2)
                                                            (i32.const 1)
                                                           )
                                                          )
                                                         )
                                                        )
                                                        (local.set $1
                                                         (i32.and
                                                          (i32.load8_u offset=1
                                                           (local.get $2)
                                                          )
                                                          (i32.const 63)
                                                         )
                                                        )
                                                        (local.set $3
                                                         (i32.and
                                                          (local.get $4)
                                                          (i32.const 31)
                                                         )
                                                        )
                                                        (if
                                                         (i32.le_u
                                                          (local.get $4)
                                                          (i32.const -33)
                                                         )
                                                         (then
                                                          (local.set $1
                                                           (i32.or
                                                            (i32.shl
                                                             (local.get $3)
                                                             (i32.const 6)
                                                            )
                                                            (local.get $1)
                                                           )
                                                          )
                                                          (br $block15
                                                           (i32.add
                                                            (local.get $2)
                                                            (i32.const 2)
                                                           )
                                                          )
                                                         )
                                                        )
                                                        (local.set $1
                                                         (i32.or
                                                          (i32.and
                                                           (i32.load8_u offset=2
                                                            (local.get $2)
                                                           )
                                                           (i32.const 63)
                                                          )
                                                          (i32.shl
                                                           (local.get $1)
                                                           (i32.const 6)
                                                          )
                                                         )
                                                        )
                                                        (br_if $block16
                                                         (i32.ge_u
                                                          (local.get $4)
                                                          (i32.const -16)
                                                         )
                                                        )
                                                        (local.set $1
                                                         (i32.or
                                                          (local.get $1)
                                                          (i32.shl
                                                           (local.get $3)
                                                           (i32.const 12)
                                                          )
                                                         )
                                                        )
                                                        (br $block15
                                                         (i32.add
                                                          (local.get $2)
                                                          (i32.const 3)
                                                         )
                                                        )
                                                       )
                                                       (br_if $block8
                                                        (i32.eq
                                                         (local.get $2)
                                                         (local.get $5)
                                                        )
                                                       )
                                                       (if
                                                        (i32.ge_s
                                                         (local.tee $4
                                                          (i32.load8_s
                                                           (local.get $2)
                                                          )
                                                         )
                                                         (i32.const 0)
                                                        )
                                                        (then
                                                         (local.set $1
                                                          (i32.and
                                                           (local.get $4)
                                                           (i32.const 255)
                                                          )
                                                         )
                                                         (br $block17
                                                          (i32.add
                                                           (local.get $2)
                                                           (i32.const 1)
                                                          )
                                                         )
                                                        )
                                                       )
                                                       (local.set $1
                                                        (i32.and
                                                         (i32.load8_u offset=1
                                                          (local.get $2)
                                                         )
                                                         (i32.const 63)
                                                        )
                                                       )
                                                       (local.set $3
                                                        (i32.and
                                                         (local.get $4)
                                                         (i32.const 31)
                                                        )
                                                       )
                                                       (if
                                                        (i32.le_u
                                                         (local.get $4)
                                                         (i32.const -33)
                                                        )
                                                        (then
                                                         (local.set $1
                                                          (i32.or
                                                           (i32.shl
                                                            (local.get $3)
                                                            (i32.const 6)
                                                           )
                                                           (local.get $1)
                                                          )
                                                         )
                                                         (br $block17
                                                          (i32.add
                                                           (local.get $2)
                                                           (i32.const 2)
                                                          )
                                                         )
                                                        )
                                                       )
                                                       (local.set $1
                                                        (i32.or
                                                         (i32.and
                                                          (i32.load8_u offset=2
                                                           (local.get $2)
                                                          )
                                                          (i32.const 63)
                                                         )
                                                         (i32.shl
                                                          (local.get $1)
                                                          (i32.const 6)
                                                         )
                                                        )
                                                       )
                                                       (br_if $block18
                                                        (i32.ge_u
                                                         (local.get $4)
                                                         (i32.const -16)
                                                        )
                                                       )
                                                       (local.set $1
                                                        (i32.or
                                                         (local.get $1)
                                                         (i32.shl
                                                          (local.get $3)
                                                          (i32.const 12)
                                                         )
                                                        )
                                                       )
                                                       (br $block17
                                                        (i32.add
                                                         (local.get $2)
                                                         (i32.const 3)
                                                        )
                                                       )
                                                      )
                                                      (local.set $1
                                                       (i32.or
                                                        (i32.and
                                                         (i32.shl
                                                          (local.get $3)
                                                          (i32.const 18)
                                                         )
                                                         (i32.const 1835008)
                                                        )
                                                        (i32.or
                                                         (i32.and
                                                          (i32.load8_u offset=3
                                                           (local.get $2)
                                                          )
                                                          (i32.const 63)
                                                         )
                                                         (i32.shl
                                                          (local.get $1)
                                                          (i32.const 6)
                                                         )
                                                        )
                                                       )
                                                      )
                                                      (i32.add
                                                       (local.get $2)
                                                       (i32.const 4)
                                                      )
                                                     )
                                                    )
                                                    (local.set $2
                                                     (block $block19 (result i32)
                                                      (block $block20
                                                       (if
                                                        (i32.eq
                                                         (local.get $1)
                                                         (i32.const 46)
                                                        )
                                                        (then
                                                         (br_if $block8
                                                          (i32.eq
                                                           (local.get $2)
                                                           (local.get $5)
                                                          )
                                                         )
                                                         (if
                                                          (i32.ge_s
                                                           (local.tee $4
                                                            (i32.load8_s
                                                             (local.get $2)
                                                            )
                                                           )
                                                           (i32.const 0)
                                                          )
                                                          (then
                                                           (local.set $1
                                                            (i32.and
                                                             (local.get $4)
                                                             (i32.const 255)
                                                            )
                                                           )
                                                           (br $block19
                                                            (i32.add
                                                             (local.get $2)
                                                             (i32.const 1)
                                                            )
                                                           )
                                                          )
                                                         )
                                                         (local.set $1
                                                          (i32.and
                                                           (i32.load8_u offset=1
                                                            (local.get $2)
                                                           )
                                                           (i32.const 63)
                                                          )
                                                         )
                                                         (local.set $3
                                                          (i32.and
                                                           (local.get $4)
                                                           (i32.const 31)
                                                          )
                                                         )
                                                         (if
                                                          (i32.le_u
                                                           (local.get $4)
                                                           (i32.const -33)
                                                          )
                                                          (then
                                                           (local.set $1
                                                            (i32.or
                                                             (i32.shl
                                                              (local.get $3)
                                                              (i32.const 6)
                                                             )
                                                             (local.get $1)
                                                            )
                                                           )
                                                           (br $block19
                                                            (i32.add
                                                             (local.get $2)
                                                             (i32.const 2)
                                                            )
                                                           )
                                                          )
                                                         )
                                                         (local.set $1
                                                          (i32.or
                                                           (i32.and
                                                            (i32.load8_u offset=2
                                                             (local.get $2)
                                                            )
                                                            (i32.const 63)
                                                           )
                                                           (i32.shl
                                                            (local.get $1)
                                                            (i32.const 6)
                                                           )
                                                          )
                                                         )
                                                         (br_if $block20
                                                          (i32.ge_u
                                                           (local.get $4)
                                                           (i32.const -16)
                                                          )
                                                         )
                                                         (local.set $1
                                                          (i32.or
                                                           (local.get $1)
                                                           (i32.shl
                                                            (local.get $3)
                                                            (i32.const 12)
                                                           )
                                                          )
                                                         )
                                                         (br $block19
                                                          (i32.add
                                                           (local.get $2)
                                                           (i32.const 3)
                                                          )
                                                         )
                                                        )
                                                       )
                                                       (br_if $block13
                                                        (i32.lt_u
                                                         (i32.sub
                                                          (i32.and
                                                           (local.get $1)
                                                           (i32.const 2097119)
                                                          )
                                                          (i32.const 65)
                                                         )
                                                         (i32.const 26)
                                                        )
                                                       )
                                                       (if
                                                        (i32.ge_u
                                                         (local.get $1)
                                                         (i32.const 170)
                                                        )
                                                        (then
                                                         (br_if $block13
                                                          (call $_RNvNtNtNtCsdHhIpgkcIfN_4core7unicode12unicode_data10alphabetic11lookup_slow
                                                           (local.get $1)
                                                          )
                                                         )
                                                        )
                                                       )
                                                       (br_if $block13
                                                        (call $_RNvXs2_NtNtCsdHhIpgkcIfN_4core3str7patterncNtB5_7Pattern15is_contained_in
                                                         (local.get $1)
                                                         (i32.const 1057340)
                                                         (i32.const 15)
                                                        )
                                                       )
                                                       (br_table $block13 $block8 $block13 $block8
                                                        (i32.sub
                                                         (local.get $1)
                                                         (i32.const 43)
                                                        )
                                                       )
                                                      )
                                                      (local.set $1
                                                       (i32.or
                                                        (i32.and
                                                         (i32.shl
                                                          (local.get $3)
                                                          (i32.const 18)
                                                         )
                                                         (i32.const 1835008)
                                                        )
                                                        (i32.or
                                                         (i32.and
                                                          (i32.load8_u offset=3
                                                           (local.get $2)
                                                          )
                                                          (i32.const 63)
                                                         )
                                                         (i32.shl
                                                          (local.get $1)
                                                          (i32.const 6)
                                                         )
                                                        )
                                                       )
                                                      )
                                                      (i32.add
                                                       (local.get $2)
                                                       (i32.const 4)
                                                      )
                                                     )
                                                    )
                                                    (br_if $block13
                                                     (i32.lt_u
                                                      (i32.sub
                                                       (i32.and
                                                        (local.get $1)
                                                        (i32.const 2097119)
                                                       )
                                                       (i32.const 65)
                                                      )
                                                      (i32.const 26)
                                                     )
                                                    )
                                                    (if
                                                     (i32.ge_u
                                                      (local.get $1)
                                                      (i32.const 170)
                                                     )
                                                     (then
                                                      (br_if $block13
                                                       (call $_RNvNtNtNtCsdHhIpgkcIfN_4core7unicode12unicode_data10alphabetic11lookup_slow
                                                        (local.get $1)
                                                       )
                                                      )
                                                     )
                                                    )
                                                    (br_if $block13
                                                     (call $_RNvXs2_NtNtCsdHhIpgkcIfN_4core3str7patterncNtB5_7Pattern15is_contained_in
                                                      (local.get $1)
                                                      (i32.const 1057340)
                                                      (i32.const 15)
                                                     )
                                                    )
                                                    (br_if $block8
                                                     (i32.gt_u
                                                      (local.tee $1
                                                       (i32.sub
                                                        (local.get $1)
                                                        (i32.const 43)
                                                       )
                                                      )
                                                      (i32.const 3)
                                                     )
                                                    )
                                                    (br_if $block8
                                                     (i32.eq
                                                      (local.get $1)
                                                      (i32.const 1)
                                                     )
                                                    )
                                                    (br $block13)
                                                   )
                                                   (local.set $1
                                                    (i32.or
                                                     (i32.and
                                                      (i32.shl
                                                       (local.get $3)
                                                       (i32.const 18)
                                                      )
                                                      (i32.const 1835008)
                                                     )
                                                     (i32.or
                                                      (i32.and
                                                       (i32.load8_u offset=3
                                                        (local.get $2)
                                                       )
                                                       (i32.const 63)
                                                      )
                                                      (i32.shl
                                                       (local.get $1)
                                                       (i32.const 6)
                                                      )
                                                     )
                                                    )
                                                   )
                                                   (i32.add
                                                    (local.get $2)
                                                    (i32.const 4)
                                                   )
                                                  )
                                                 )
                                                 (br_if $block13
                                                  (i32.lt_u
                                                   (i32.sub
                                                    (i32.and
                                                     (local.get $1)
                                                     (i32.const 2097119)
                                                    )
                                                    (i32.const 65)
                                                   )
                                                   (i32.const 26)
                                                  )
                                                 )
                                                 (if
                                                  (i32.ge_u
                                                   (local.get $1)
                                                   (i32.const 170)
                                                  )
                                                  (then
                                                   (br_if $block13
                                                    (call $_RNvNtNtNtCsdHhIpgkcIfN_4core7unicode12unicode_data10alphabetic11lookup_slow
                                                     (local.get $1)
                                                    )
                                                   )
                                                  )
                                                 )
                                                 (br_if $block13
                                                  (call $_RNvXs2_NtNtCsdHhIpgkcIfN_4core3str7patterncNtB5_7Pattern15is_contained_in
                                                   (local.get $1)
                                                   (i32.const 1057340)
                                                   (i32.const 15)
                                                  )
                                                 )
                                                 (br_if $block8
                                                  (i32.gt_u
                                                   (local.tee $1
                                                    (i32.sub
                                                     (local.get $1)
                                                     (i32.const 43)
                                                    )
                                                   )
                                                   (i32.const 3)
                                                  )
                                                 )
                                                 (br_if $block8
                                                  (i32.eq
                                                   (local.get $1)
                                                   (i32.const 1)
                                                  )
                                                 )
                                                )
                                                (drop
                                                 (br_if $block14
                                                  (i32.const 1)
                                                  (i32.eq
                                                   (local.get $2)
                                                   (local.get $5)
                                                  )
                                                 )
                                                )
                                                (loop $label2
                                                 (local.set $2
                                                  (block $block21 (result i32)
                                                   (if
                                                    (i32.ge_s
                                                     (local.tee $4
                                                      (i32.load8_s
                                                       (local.get $2)
                                                      )
                                                     )
                                                     (i32.const 0)
                                                    )
                                                    (then
                                                     (local.set $1
                                                      (i32.and
                                                       (local.get $4)
                                                       (i32.const 255)
                                                      )
                                                     )
                                                     (br $block21
                                                      (i32.add
                                                       (local.get $2)
                                                       (i32.const 1)
                                                      )
                                                     )
                                                    )
                                                   )
                                                   (local.set $1
                                                    (i32.and
                                                     (i32.load8_u offset=1
                                                      (local.get $2)
                                                     )
                                                     (i32.const 63)
                                                    )
                                                   )
                                                   (local.set $3
                                                    (i32.and
                                                     (local.get $4)
                                                     (i32.const 31)
                                                    )
                                                   )
                                                   (if
                                                    (i32.le_u
                                                     (local.get $4)
                                                     (i32.const -33)
                                                    )
                                                    (then
                                                     (local.set $1
                                                      (i32.or
                                                       (i32.shl
                                                        (local.get $3)
                                                        (i32.const 6)
                                                       )
                                                       (local.get $1)
                                                      )
                                                     )
                                                     (br $block21
                                                      (i32.add
                                                       (local.get $2)
                                                       (i32.const 2)
                                                      )
                                                     )
                                                    )
                                                   )
                                                   (local.set $1
                                                    (i32.or
                                                     (i32.and
                                                      (i32.load8_u offset=2
                                                       (local.get $2)
                                                      )
                                                      (i32.const 63)
                                                     )
                                                     (i32.shl
                                                      (local.get $1)
                                                      (i32.const 6)
                                                     )
                                                    )
                                                   )
                                                   (if
                                                    (i32.lt_u
                                                     (local.get $4)
                                                     (i32.const -16)
                                                    )
                                                    (then
                                                     (local.set $1
                                                      (i32.or
                                                       (local.get $1)
                                                       (i32.shl
                                                        (local.get $3)
                                                        (i32.const 12)
                                                       )
                                                      )
                                                     )
                                                     (br $block21
                                                      (i32.add
                                                       (local.get $2)
                                                       (i32.const 3)
                                                      )
                                                     )
                                                    )
                                                   )
                                                   (br_if $block22
                                                    (i32.eq
                                                     (local.tee $1
                                                      (i32.or
                                                       (i32.and
                                                        (i32.shl
                                                         (local.get $3)
                                                         (i32.const 18)
                                                        )
                                                        (i32.const 1835008)
                                                       )
                                                       (i32.or
                                                        (i32.and
                                                         (i32.load8_u offset=3
                                                          (local.get $2)
                                                         )
                                                         (i32.const 63)
                                                        )
                                                        (i32.shl
                                                         (local.get $1)
                                                         (i32.const 6)
                                                        )
                                                       )
                                                      )
                                                     )
                                                     (i32.const 1114112)
                                                    )
                                                   )
                                                   (i32.add
                                                    (local.get $2)
                                                    (i32.const 4)
                                                   )
                                                  )
                                                 )
                                                 (block $block23
                                                  (br_if $block23
                                                   (i32.lt_u
                                                    (i32.sub
                                                     (i32.and
                                                      (local.get $1)
                                                      (i32.const 2097119)
                                                     )
                                                     (i32.const 65)
                                                    )
                                                    (i32.const 26)
                                                   )
                                                  )
                                                  (if
                                                   (i32.ge_u
                                                    (local.get $1)
                                                    (i32.const 170)
                                                   )
                                                   (then
                                                    (br_if $block23
                                                     (call $_RNvNtNtNtCsdHhIpgkcIfN_4core7unicode12unicode_data10alphabetic11lookup_slow
                                                      (local.get $1)
                                                     )
                                                    )
                                                   )
                                                  )
                                                  (br_if $block23
                                                   (call $_RNvXs2_NtNtCsdHhIpgkcIfN_4core3str7patterncNtB5_7Pattern15is_contained_in
                                                    (local.get $1)
                                                    (i32.const 1057340)
                                                    (i32.const 15)
                                                   )
                                                  )
                                                  (br_if $block23
                                                   (i32.lt_u
                                                    (i32.sub
                                                     (local.get $1)
                                                     (i32.const 48)
                                                    )
                                                    (i32.const 10)
                                                   )
                                                  )
                                                  (br_if $block8
                                                   (i32.eqz
                                                    (call $_RNvXs2_NtNtCsdHhIpgkcIfN_4core3str7patterncNtB5_7Pattern15is_contained_in
                                                     (local.get $1)
                                                     (i32.const 1057069)
                                                     (i32.const 3)
                                                    )
                                                   )
                                                  )
                                                 )
                                                 (br_if $label2
                                                  (i32.ne
                                                   (local.get $2)
                                                   (local.get $5)
                                                  )
                                                 )
                                                )
                                                (br $block14
                                                 (i32.const 1)
                                                )
                                               )
                                               (br $block14
                                                (i32.const 0)
                                               )
                                              )
                                              (i32.const 1)
                                             )
                                            )
                                            (i32.store
                                             (i32.const 1137992)
                                             (i32.sub
                                              (i32.load
                                               (i32.const 1137992)
                                              )
                                              (i32.const 1)
                                             )
                                            )
                                            (local.get $scratch)
                                           )
                                          )
                                         )
                                        )
                                        (global.set $__stack_pointer
                                         (local.tee $1
                                          (i32.sub
                                           (global.get $__stack_pointer)
                                           (i32.const 16)
                                          )
                                         )
                                        )
                                        (i64.store
                                         (local.get $1)
                                         (i64.or
                                          (i64.extend_i32_u
                                           (i32.add
                                            (local.get $1)
                                            (i32.const 15)
                                           )
                                          )
                                          (i64.const 55834574848)
                                         )
                                        )
                                        (call $_RNvNtCsdHhIpgkcIfN_4core9panicking9panic_fmt
                                         (i32.const 1049688)
                                         (local.get $1)
                                         (i32.const 1061216)
                                        )
                                        (unreachable)
                                       )
                                       (call $_RINvNtNtCset5xJoy1xWQ_3std3sys9backtrace26___rust_end_short_backtraceNCNvNtB6_5alloc8rust_oom0zEB6_
                                        (i32.const 30)
                                       )
                                       (unreachable)
                                      )
                                      (i32.const 1)
                                     )
                                     (then
                                      (struct.new $type132
                                       (i32.const 1)
                                       (struct.new $type21
                                        (i32.const 4)
                                        (struct.new $type22
                                         (call $snail:datum/token-intern
                                          (local.get $7)
                                         )
                                        )
                                       )
                                      )
                                     )
                                     (else
                                      (call $snail:datum/token-close
                                       (local.get $7)
                                      )
                                      (struct.new $type133
                                       (i32.const 2)
                                       (global.get $string1)
                                      )
                                     )
                                    )
                                   )
                                  )
                                 )
                                )
                                (i32.const 1)
                               )
                               (then
                                (struct.new $type164
                                 (i32.const 0)
                                 (struct.get $type132 1
                                  (ref.cast (ref $type132)
                                   (local.get $17)
                                  )
                                 )
                                )
                               )
                               (else
                                (if (result (ref $type170))
                                 (i32.eq
                                  (struct.get $type130 0
                                   (local.get $17)
                                  )
                                  (i32.const 2)
                                 )
                                 (then
                                  (struct.new $type170
                                   (i32.const 6)
                                   (struct.get $type133 1
                                    (ref.cast (ref $type133)
                                     (local.get $17)
                                    )
                                   )
                                  )
                                 )
                                 (else
                                  (unreachable)
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
      (unreachable)
     )
    )
   )
  )
  (if
   (i32.eqz
    (global.get $ready527)
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
  (return_call $function154
   (local.get $0)
  )
 )
