(func $function137 (type $call158) (param $0 (ref $type58)) (result (ref $type159))
  (local $1 i64)
  (local $2 i32)
  (local $3 i32)
  (local $4 (ref $type18))
  (local $5 (ref $type18))
  (local $6 (ref $type18))
  (local $7 (ref $type68))
  (local $8 (ref $type121))
  (local $9 (ref $type150))
  (local $10 (ref $type138))
  (local $11 (ref $type177))
  (local $12 (ref $type159))
  (drop
   (ref.as_non_null
    (global.get $global466)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global135)
   )
  )
  (local.set $2
   (call $foreign7
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
    (global.get $global468)
   )
  )
  (block $block
   (return
    (if (result (ref $type161))
     (i64.lt_s
      (local.tee $1
       (if (result i64)
        (ref.test (ref $type69)
         (local.tee $7
          (if (result (ref $type68))
           (i32.eq
            (local.get $2)
            (i32.const -1)
           )
           (then
            (global.get $empty69)
           )
           (else
            (if
             (i64.gt_u
              (local.tee $1
               (i64.extend_i32_s
                (local.get $2)
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
               (local.get $1)
               (i64.const 57343)
              )
              (i64.ge_u
               (local.get $1)
               (i64.const 55296)
              )
             )
             (then
              (unreachable)
             )
            )
            (struct.new $type70
             (i32.wrap_i64
              (local.get $1)
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
            (local.get $7)
           )
          )
         )
        )
       )
      )
      (i64.const 0)
     )
     (then
      (global.get $empty161)
     )
     (else
      (drop
       (ref.as_non_null
        (global.get $global472)
       )
      )
      (br_if $block
       (if (result i32)
        (i64.ge_s
         (local.get $1)
         (i64.const 0)
        )
        (then
         (if
          (i64.gt_u
           (local.get $1)
           (i64.const 1114111)
          )
          (then
           (unreachable)
          )
         )
         (if
          (i32.and
           (i64.le_u
            (local.get $1)
            (i64.const 57343)
           )
           (i64.ge_u
            (local.get $1)
            (i64.const 55296)
           )
          )
          (then
           (unreachable)
          )
         )
         (i32.eq
          (call $foreign25
           (i32.wrap_i64
            (local.get $1)
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
        (global.get $global474)
       )
      )
      (if
       (i64.eq
        (local.get $1)
        (i64.const 59)
       )
       (then
        (drop
         (ref.as_non_null
          (global.get $global477)
         )
        )
        (drop
         (call $function142
          (local.get $0)
         )
        )
        (br $block)
       )
       (else
        (if
         (i32.eqz
          (global.get $ready482)
         )
         (then
          (unreachable)
         )
        )
        (drop
         (ref.as_non_null
          (global.get $global482)
         )
        )
        (drop
         (ref.as_non_null
          (global.get $global474)
         )
        )
        (return
         (if (result (ref $type159))
          (i64.eq
           (local.get $1)
           (i64.const 40)
          )
          (then
           (struct.new $type164
            (i32.const 4)
            (i64.const 0)
           )
          )
          (else
           (drop
            (ref.as_non_null
             (global.get $global474)
            )
           )
           (if (result (ref $type159))
            (i64.eq
             (local.get $1)
             (i64.const 41)
            )
            (then
             (global.get $empty162)
            )
            (else
             (drop
              (ref.as_non_null
               (global.get $global474)
              )
             )
             (if (result (ref $type159))
              (i64.eq
               (local.get $1)
               (i64.const 39)
              )
              (then
               (struct.new $type165
                (i32.const 5)
                (global.get $string7)
               )
              )
              (else
               (drop
                (ref.as_non_null
                 (global.get $global474)
                )
               )
               (if (result (ref $type159))
                (i64.eq
                 (local.get $1)
                 (i64.const 96)
                )
                (then
                 (struct.new $type165
                  (i32.const 5)
                  (global.get $string6)
                 )
                )
                (else
                 (drop
                  (ref.as_non_null
                   (global.get $global474)
                  )
                 )
                 (if (result (ref $type159))
                  (i64.eq
                   (local.get $1)
                   (i64.const 44)
                  )
                  (then
                   (drop
                    (ref.as_non_null
                     (global.get $global485)
                    )
                   )
                   (drop
                    (ref.as_non_null
                     (global.get $global488)
                    )
                   )
                   (drop
                    (ref.as_non_null
                     (global.get $global137)
                    )
                   )
                   (local.set $2
                    (call $foreign8
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
                     (global.get $global468)
                    )
                   )
                   (drop
                    (ref.as_non_null
                     (global.get $global474)
                    )
                   )
                   (struct.new $type165
                    (i32.const 5)
                    (select (result (ref $type18))
                     (global.get $string5)
                     (global.get $string4)
                     (if (result i32)
                      (i64.eq
                       (if (result i64)
                        (ref.test (ref $type69)
                         (local.tee $7
                          (if (result (ref $type68))
                           (i32.eq
                            (local.get $2)
                            (i32.const -1)
                           )
                           (then
                            (global.get $empty69)
                           )
                           (else
                            (if
                             (i64.gt_u
                              (local.tee $1
                               (i64.extend_i32_s
                                (local.get $2)
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
                               (local.get $1)
                               (i64.const 57343)
                              )
                              (i64.ge_u
                               (local.get $1)
                               (i64.const 55296)
                              )
                             )
                             (then
                              (unreachable)
                             )
                            )
                            (struct.new $type70
                             (i32.wrap_i64
                              (local.get $1)
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
                            (local.get $7)
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
                       (local.set $2
                        (call $foreign7
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
                          (local.get $2)
                          (i32.const -1)
                         )
                         (then
                          (global.get $empty69)
                         )
                         (else
                          (if
                           (i64.gt_u
                            (local.tee $1
                             (i64.extend_i32_s
                              (local.get $2)
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
                             (local.get $1)
                             (i64.const 57343)
                            )
                            (i64.ge_u
                             (local.get $1)
                             (i64.const 55296)
                            )
                           )
                           (then
                            (unreachable)
                           )
                          )
                          (struct.new $type70
                           (i32.wrap_i64
                            (local.get $1)
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
                     (global.get $global474)
                    )
                   )
                   (if (result (ref $type166))
                    (i64.eq
                     (local.get $1)
                     (i64.const 34)
                    )
                    (then
                     (if
                      (i32.eqz
                       (global.get $ready490)
                      )
                      (then
                       (unreachable)
                      )
                     )
                     (drop
                      (ref.as_non_null
                       (global.get $global490)
                      )
                     )
                     (return_call $function146
                      (local.get $0)
                      (i32.const 34)
                      (i32.const 0)
                     )
                    )
                    (else
                     (drop
                      (ref.as_non_null
                       (global.get $global474)
                      )
                     )
                     (if (result (ref $type166))
                      (i64.eq
                       (local.get $1)
                       (i64.const 124)
                      )
                      (then
                       (if
                        (i32.eqz
                         (global.get $ready490)
                        )
                        (then
                         (unreachable)
                        )
                       )
                       (drop
                        (ref.as_non_null
                         (global.get $global490)
                        )
                       )
                       (return_call $function146
                        (local.get $0)
                        (i32.const 124)
                        (i32.const 1)
                       )
                      )
                      (else
                       (drop
                        (ref.as_non_null
                         (global.get $global474)
                        )
                       )
                       (if (result (ref $type166))
                        (i64.eq
                         (local.get $1)
                         (i64.const 35)
                        )
                        (then
                         (if
                          (i32.eqz
                           (global.get $ready563)
                          )
                          (then
                           (unreachable)
                          )
                         )
                         (drop
                          (ref.as_non_null
                           (global.get $global563)
                          )
                         )
                         (drop
                          (ref.as_non_null
                           (global.get $global466)
                          )
                         )
                         (drop
                          (ref.as_non_null
                           (global.get $global135)
                          )
                         )
                         (local.set $2
                          (call $foreign7
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
                           (global.get $global468)
                          )
                         )
                         (return
                          (if (result (ref $type159))
                           (i64.lt_s
                            (local.tee $1
                             (if (result i64)
                              (ref.test (ref $type69)
                               (local.tee $7
                                (if (result (ref $type68))
                                 (i32.eq
                                  (local.get $2)
                                  (i32.const -1)
                                 )
                                 (then
                                  (global.get $empty69)
                                 )
                                 (else
                                  (if
                                   (i64.gt_u
                                    (local.tee $1
                                     (i64.extend_i32_s
                                      (local.get $2)
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
                                     (local.get $1)
                                     (i64.const 57343)
                                    )
                                    (i64.ge_u
                                     (local.get $1)
                                     (i64.const 55296)
                                    )
                                   )
                                   (then
                                    (unreachable)
                                   )
                                  )
                                  (struct.new $type70
                                   (i32.wrap_i64
                                    (local.get $1)
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
                                  (local.get $7)
                                 )
                                )
                               )
                              )
                             )
                            )
                            (i64.const 0)
                           )
                           (then
                            (struct.new $type166
                             (i32.const 6)
                             (global.get $string18)
                            )
                           )
                           (else
                            (drop
                             (ref.as_non_null
                              (global.get $global474)
                             )
                            )
                            (if (result (ref $type159))
                             (i64.eq
                              (local.get $1)
                              (i64.const 40)
                             )
                             (then
                              (struct.new $type164
                               (i32.const 4)
                               (i64.const 1)
                              )
                             )
                             (else
                              (drop
                               (ref.as_non_null
                                (global.get $global474)
                               )
                              )
                              (if (result (ref $type159))
                               (i64.eq
                                (local.get $1)
                                (i64.const 59)
                               )
                               (then
                                (drop
                                 (ref.as_non_null
                                  (global.get $global566)
                                 )
                                )
                                (drop
                                 (ref.as_non_null
                                  (global.get $global461)
                                 )
                                )
                                (if
                                 (i32.eqz
                                  (global.get $ready463)
                                 )
                                 (then
                                  (unreachable)
                                 )
                                )
                                (drop
                                 (ref.as_non_null
                                  (global.get $global463)
                                 )
                                )
                                (local.set $12
                                 (call $function137
                                  (local.get $0)
                                 )
                                )
                                (if
                                 (i32.eqz
                                  (global.get $ready631)
                                 )
                                 (then
                                  (unreachable)
                                 )
                                )
                                (drop
                                 (ref.as_non_null
                                  (global.get $global631)
                                 )
                                )
                                (if (result (ref $type166))
                                 (i32.eq
                                  (struct.get $type138 0
                                   (local.tee $10
                                    (call $function180
                                     (local.get $0)
                                     (local.get $12)
                                    )
                                   )
                                  )
                                  (i32.const 1)
                                 )
                                 (then
                                  (drop
                                   (ref.cast (ref $type140)
                                    (local.get $10)
                                   )
                                  )
                                  (br $block)
                                 )
                                 (else
                                  (if (result (ref $type166))
                                   (struct.get $type138 0
                                    (local.get $10)
                                   )
                                   (then
                                    (struct.new $type166
                                     (i32.const 6)
                                     (struct.get $type141 1
                                      (ref.cast (ref $type141)
                                       (local.get $10)
                                      )
                                     )
                                    )
                                   )
                                   (else
                                    (struct.new $type166
                                     (i32.const 6)
                                     (global.get $string19)
                                    )
                                   )
                                  )
                                 )
                                )
                               )
                               (else
                                (drop
                                 (ref.as_non_null
                                  (global.get $global474)
                                 )
                                )
                                (if (result (ref $type159))
                                 (i64.eq
                                  (local.get $1)
                                  (i64.const 124)
                                 )
                                 (then
                                  (drop
                                   (ref.as_non_null
                                    (global.get $global571)
                                   )
                                  )
                                  (if (result (ref $type166))
                                   (call $function165
                                    (local.get $0)
                                    (i64.const 1)
                                   )
                                   (then
                                    (drop
                                     (ref.as_non_null
                                      (global.get $global463)
                                     )
                                    )
                                    (return_call $function137
                                     (local.get $0)
                                    )
                                   )
                                   (else
                                    (struct.new $type166
                                     (i32.const 6)
                                     (global.get $string17)
                                    )
                                   )
                                  )
                                 )
                                 (else
                                  (drop
                                   (ref.as_non_null
                                    (global.get $global474)
                                   )
                                  )
                                  (if (result (ref $type159))
                                   (i64.eq
                                    (local.get $1)
                                    (i64.const 92)
                                   )
                                   (then
                                    (if
                                     (i32.eqz
                                      (global.get $ready576)
                                     )
                                     (then
                                      (unreachable)
                                     )
                                    )
                                    (drop
                                     (ref.as_non_null
                                      (global.get $global576)
                                     )
                                    )
                                    (drop
                                     (ref.as_non_null
                                      (global.get $global466)
                                     )
                                    )
                                    (if (result (ref $type159))
                                     (i64.lt_s
                                      (local.tee $1
                                       (call $function138
                                        (local.get $0)
                                       )
                                      )
                                      (i64.const 0)
                                     )
                                     (then
                                      (struct.new $type166
                                       (i32.const 6)
                                       (global.get $string20)
                                      )
                                     )
                                     (else
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global579)
                                       )
                                      )
                                      (if (result (ref $type160))
                                       (call $function167
                                        (local.get $1)
                                       )
                                       (then
                                        (if
                                         (i64.gt_u
                                          (local.get $1)
                                          (i64.const 1114111)
                                         )
                                         (then
                                          (unreachable)
                                         )
                                        )
                                        (if
                                         (i32.and
                                          (i64.le_u
                                           (local.get $1)
                                           (i64.const 57343)
                                          )
                                          (i64.ge_u
                                           (local.get $1)
                                           (i64.const 55296)
                                          )
                                         )
                                         (then
                                          (unreachable)
                                         )
                                        )
                                        (struct.new $type160
                                         (i32.const 0)
                                         (struct.new $type16
                                          (i32.const 2)
                                          (i32.wrap_i64
                                           (local.get $1)
                                          )
                                         )
                                        )
                                       )
                                       (else
                                        (drop
                                         (ref.as_non_null
                                          (global.get $global587)
                                         )
                                        )
                                        (drop
                                         (ref.as_non_null
                                          (global.get $global498)
                                         )
                                        )
                                        (drop
                                         (ref.as_non_null
                                          (global.get $global61)
                                         )
                                        )
                                        (local.set $9
                                         (struct.new $type150
                                          (struct.new $type151
                                           (call $string-new
                                            (i32.const 32)
                                           )
                                          )
                                          (struct.new_default $type152)
                                         )
                                        )
                                        (if
                                         (i64.gt_u
                                          (local.get $1)
                                          (i64.const 1114111)
                                         )
                                         (then
                                          (unreachable)
                                         )
                                        )
                                        (if
                                         (i32.and
                                          (i64.le_u
                                           (local.get $1)
                                           (i64.const 57343)
                                          )
                                          (i64.ge_u
                                           (local.get $1)
                                           (i64.const 55296)
                                          )
                                         )
                                         (then
                                          (unreachable)
                                         )
                                        )
                                        (drop
                                         (ref.as_non_null
                                          (global.get $global547)
                                         )
                                        )
                                        (call $function160
                                         (local.get $9)
                                         (i32.wrap_i64
                                          (local.get $1)
                                         )
                                        )
                                        (local.set $4
                                         (call $function170
                                          (local.get $0)
                                          (local.get $9)
                                          (i32.const 0)
                                          (i32.const 1)
                                         )
                                        )
                                        (if
                                         (i32.eqz
                                          (global.get $ready592)
                                         )
                                         (then
                                          (unreachable)
                                         )
                                        )
                                        (drop
                                         (ref.as_non_null
                                          (global.get $global592)
                                         )
                                        )
                                        (return
                                         (if (result (ref $type159))
                                          (i64.eq
                                           (local.tee $1
                                            (i64.extend_i32_u
                                             (struct.get $type18 1
                                              (local.get $4)
                                             )
                                            )
                                           )
                                           (i64.const 1)
                                          )
                                          (then
                                           (if
                                            (i64.eqz
                                             (local.get $1)
                                            )
                                            (then
                                             (unreachable)
                                            )
                                           )
                                           (struct.new $type160
                                            (i32.const 0)
                                            (struct.new $type16
                                             (i32.const 2)
                                             (array.get $type19
                                              (struct.get $type18 2
                                               (local.get $4)
                                              )
                                              (i32.const 0)
                                             )
                                            )
                                           )
                                          )
                                          (else
                                           (drop
                                            (ref.as_non_null
                                             (global.get $global595)
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
                                           (local.set $4
                                            (call $function173
                                             (if (result (ref $type18))
                                              (i64.lt_s
                                               (local.tee $1
                                                (i64.extend_i32_u
                                                 (struct.get $type18 1
                                                  (local.get $4)
                                                 )
                                                )
                                               )
                                               (local.get $1)
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
                                                 (local.get $1)
                                                 (i64.const 4294967294)
                                                )
                                                (then
                                                 (unreachable)
                                                )
                                               )
                                               (call $string-copy
                                                (local.tee $5
                                                 (call $string-new
                                                  (i32.wrap_i64
                                                   (local.get $1)
                                                  )
                                                 )
                                                )
                                                (i64.const 0)
                                                (local.get $4)
                                                (local.get $1)
                                               )
                                               (local.get $5)
                                              )
                                             )
                                             (i32.const 0)
                                             (i32.const 1)
                                             (i64.const 0)
                                            )
                                           )
                                           (if
                                            (i32.eqz
                                             (global.get $ready601)
                                            )
                                            (then
                                             (unreachable)
                                            )
                                           )
                                           (drop
                                            (ref.as_non_null
                                             (global.get $global601)
                                            )
                                           )
                                           (drop
                                            (ref.as_non_null
                                             (global.get $global103)
                                            )
                                           )
                                           (if (result (ref $type159))
                                            (struct.get $type177 0
                                             (local.tee $11
                                              (if (result (ref $type177))
                                               (if (result i32)
                                                (i64.eq
                                                 (i64.extend_i32_u
                                                  (struct.get $type18 1
                                                   (local.get $4)
                                                  )
                                                 )
                                                 (i64.const 5)
                                                )
                                                (then
                                                 (call $function40
                                                  (local.get $4)
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
                                                (struct.new $type178
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
                                                (if (result (ref $type177))
                                                 (if (result i32)
                                                  (i64.eq
                                                   (i64.extend_i32_u
                                                    (struct.get $type18 1
                                                     (local.get $4)
                                                    )
                                                   )
                                                   (i64.const 9)
                                                  )
                                                  (then
                                                   (call $function40
                                                    (local.get $4)
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
                                                  (struct.new $type178
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
                                                  (if (result (ref $type177))
                                                   (if (result i32)
                                                    (i64.eq
                                                     (i64.extend_i32_u
                                                      (struct.get $type18 1
                                                       (local.get $4)
                                                      )
                                                     )
                                                     (i64.const 6)
                                                    )
                                                    (then
                                                     (call $function40
                                                      (local.get $4)
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
                                                    (struct.new $type178
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
                                                    (if (result (ref $type177))
                                                     (if (result i32)
                                                      (i64.eq
                                                       (i64.extend_i32_u
                                                        (struct.get $type18 1
                                                         (local.get $4)
                                                        )
                                                       )
                                                       (i64.const 6)
                                                      )
                                                      (then
                                                       (call $function40
                                                        (local.get $4)
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
                                                      (struct.new $type178
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
                                                      (if (result (ref $type177))
                                                       (if (result i32)
                                                        (i64.eq
                                                         (i64.extend_i32_u
                                                          (struct.get $type18 1
                                                           (local.get $4)
                                                          )
                                                         )
                                                         (i64.const 7)
                                                        )
                                                        (then
                                                         (call $function40
                                                          (local.get $4)
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
                                                        (struct.new $type178
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
                                                        (if (result (ref $type177))
                                                         (if (result i32)
                                                          (i64.eq
                                                           (i64.extend_i32_u
                                                            (struct.get $type18 1
                                                             (local.get $4)
                                                            )
                                                           )
                                                           (i64.const 4)
                                                          )
                                                          (then
                                                           (call $function40
                                                            (local.get $4)
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
                                                          (struct.new_default $type178)
                                                         )
                                                         (else
                                                          (drop
                                                           (ref.as_non_null
                                                            (global.get $global103)
                                                           )
                                                          )
                                                          (if (result (ref $type177))
                                                           (if (result i32)
                                                            (i64.eq
                                                             (i64.extend_i32_u
                                                              (struct.get $type18 1
                                                               (local.get $4)
                                                              )
                                                             )
                                                             (i64.const 6)
                                                            )
                                                            (then
                                                             (call $function40
                                                              (local.get $4)
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
                                                            (struct.new $type178
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
                                                            (if (result (ref $type177))
                                                             (if (result i32)
                                                              (i64.eq
                                                               (i64.extend_i32_u
                                                                (struct.get $type18 1
                                                                 (local.get $4)
                                                                )
                                                               )
                                                               (i64.const 5)
                                                              )
                                                              (then
                                                               (call $function40
                                                                (local.get $4)
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
                                                              (struct.new $type178
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
                                                              (if (result (ref $type177))
                                                               (if (result i32)
                                                                (i64.eq
                                                                 (i64.extend_i32_u
                                                                  (struct.get $type18 1
                                                                   (local.get $4)
                                                                  )
                                                                 )
                                                                 (i64.const 3)
                                                                )
                                                                (then
                                                                 (call $function40
                                                                  (local.get $4)
                                                                  (global.get $string23)
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
                                                                (struct.new $type178
                                                                 (i32.const 0)
                                                                 (i32.const 9)
                                                                )
                                                               )
                                                               (else
                                                                (if
                                                                 (i64.eqz
                                                                  (i64.extend_i32_u
                                                                   (struct.get $type18 1
                                                                    (local.get $4)
                                                                   )
                                                                  )
                                                                 )
                                                                 (then
                                                                  (unreachable)
                                                                 )
                                                                )
                                                                (if (result (ref $type177))
                                                                 (i32.eq
                                                                  (array.get $type19
                                                                   (struct.get $type18 2
                                                                    (local.get $4)
                                                                   )
                                                                   (i32.const 0)
                                                                  )
                                                                  (i32.const 120)
                                                                 )
                                                                 (then
                                                                  (drop
                                                                   (ref.as_non_null
                                                                    (global.get $global603)
                                                                   )
                                                                  )
                                                                  (call $function176
                                                                   (local.get $4)
                                                                   (i32.const 0)
                                                                   (i32.const 1)
                                                                   (i64.const 1)
                                                                   (i64.const 0)
                                                                  )
                                                                 )
                                                                 (else
                                                                  (struct.new $type180
                                                                   (i32.const 2)
                                                                   (global.get $string22)
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
                                             (if (result (ref $type166))
                                              (i32.eq
                                               (struct.get $type177 0
                                                (local.get $11)
                                               )
                                               (i32.const 2)
                                              )
                                              (then
                                               (struct.new $type166
                                                (i32.const 6)
                                                (struct.get $type180 1
                                                 (ref.cast (ref $type180)
                                                  (local.get $11)
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
                                             (struct.new $type160
                                              (i32.const 0)
                                              (struct.new $type16
                                               (i32.const 2)
                                               (struct.get $type178 1
                                                (ref.cast (ref $type178)
                                                 (local.get $11)
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
                                      (global.get $global474)
                                     )
                                    )
                                    (if (result (ref $type159))
                                     (if (result i32)
                                      (local.tee $2
                                       (i64.eq
                                        (local.get $1)
                                        (i64.const 117)
                                       )
                                      )
                                      (then
                                       (local.get $2)
                                      )
                                      (else
                                       (drop
                                        (ref.as_non_null
                                         (global.get $global474)
                                        )
                                       )
                                       (i64.eq
                                        (local.get $1)
                                        (i64.const 85)
                                       )
                                      )
                                     )
                                     (then
                                      (if
                                       (i32.eqz
                                        (global.get $ready613)
                                       )
                                       (then
                                        (unreachable)
                                       )
                                      )
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global613)
                                       )
                                      )
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global485)
                                       )
                                      )
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global488)
                                       )
                                      )
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global137)
                                       )
                                      )
                                      (local.set $2
                                       (call $foreign8
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
                                        (global.get $global468)
                                       )
                                      )
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global474)
                                       )
                                      )
                                      (if (result (ref $type159))
                                       (if (result i32)
                                        (if (result i32)
                                         (i64.eq
                                          (if (result i64)
                                           (ref.test (ref $type69)
                                            (local.tee $7
                                             (if (result (ref $type68))
                                              (i32.eq
                                               (local.get $2)
                                               (i32.const -1)
                                              )
                                              (then
                                               (global.get $empty69)
                                              )
                                              (else
                                               (if
                                                (i64.gt_u
                                                 (local.tee $1
                                                  (i64.extend_i32_s
                                                   (local.get $2)
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
                                                  (local.get $1)
                                                  (i64.const 57343)
                                                 )
                                                 (i64.ge_u
                                                  (local.get $1)
                                                  (i64.const 55296)
                                                 )
                                                )
                                                (then
                                                 (unreachable)
                                                )
                                               )
                                               (struct.new $type70
                                                (i32.wrap_i64
                                                 (local.get $1)
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
                                               (local.get $7)
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
                                          (local.set $2
                                           (call $foreign7
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
                                             (local.get $2)
                                             (i32.const -1)
                                            )
                                            (then
                                             (global.get $empty69)
                                            )
                                            (else
                                             (if
                                              (i64.gt_u
                                               (local.tee $1
                                                (i64.extend_i32_s
                                                 (local.get $2)
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
                                                (local.get $1)
                                                (i64.const 57343)
                                               )
                                               (i64.ge_u
                                                (local.get $1)
                                                (i64.const 55296)
                                               )
                                              )
                                              (then
                                               (unreachable)
                                              )
                                             )
                                             (struct.new $type70
                                              (i32.wrap_i64
                                               (local.get $1)
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
                                           (global.get $global485)
                                          )
                                         )
                                         (drop
                                          (ref.as_non_null
                                           (global.get $global488)
                                          )
                                         )
                                         (drop
                                          (ref.as_non_null
                                           (global.get $global137)
                                          )
                                         )
                                         (local.set $2
                                          (call $foreign8
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
                                           (global.get $global468)
                                          )
                                         )
                                         (drop
                                          (ref.as_non_null
                                           (global.get $global474)
                                          )
                                         )
                                         (if (result i32)
                                          (i64.eq
                                           (if (result i64)
                                            (ref.test (ref $type69)
                                             (local.tee $7
                                              (if (result (ref $type68))
                                               (i32.eq
                                                (local.get $2)
                                                (i32.const -1)
                                               )
                                               (then
                                                (global.get $empty69)
                                               )
                                               (else
                                                (if
                                                 (i64.gt_u
                                                  (local.tee $1
                                                   (i64.extend_i32_s
                                                    (local.get $2)
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
                                                   (local.get $1)
                                                   (i64.const 57343)
                                                  )
                                                  (i64.ge_u
                                                   (local.get $1)
                                                   (i64.const 55296)
                                                  )
                                                 )
                                                 (then
                                                  (unreachable)
                                                 )
                                                )
                                                (struct.new $type70
                                                 (i32.wrap_i64
                                                  (local.get $1)
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
                                                (local.get $7)
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
                                           (local.set $2
                                            (call $foreign7
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
                                              (local.get $2)
                                              (i32.const -1)
                                             )
                                             (then
                                              (global.get $empty69)
                                             )
                                             (else
                                              (if
                                               (i64.gt_u
                                                (local.tee $1
                                                 (i64.extend_i32_s
                                                  (local.get $2)
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
                                                 (local.get $1)
                                                 (i64.const 57343)
                                                )
                                                (i64.ge_u
                                                 (local.get $1)
                                                 (i64.const 55296)
                                                )
                                               )
                                               (then
                                                (unreachable)
                                               )
                                              )
                                              (struct.new $type70
                                               (i32.wrap_i64
                                                (local.get $1)
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
                                        (struct.new $type164
                                         (i32.const 4)
                                         (i64.const 2)
                                        )
                                       )
                                       (else
                                        (struct.new $type166
                                         (i32.const 6)
                                         (global.get $string33)
                                        )
                                       )
                                      )
                                     )
                                     (else
                                      (drop
                                       (ref.as_non_null
                                        (global.get $global474)
                                       )
                                      )
                                      (if (result (ref $type159))
                                       (i64.eq
                                        (local.get $1)
                                        (i64.const 33)
                                       )
                                       (then
                                        (struct.new $type166
                                         (i32.const 6)
                                         (global.get $string16)
                                        )
                                       )
                                       (else
                                        (if (result (ref $type159))
                                         (i32.and
                                          (i64.le_s
                                           (local.get $1)
                                           (i64.const 57)
                                          )
                                          (i64.ge_s
                                           (local.get $1)
                                           (i64.const 48)
                                          )
                                         )
                                         (then
                                          (struct.new $type166
                                           (i32.const 6)
                                           (global.get $string15)
                                          )
                                         )
                                         (else
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global587)
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global498)
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global61)
                                           )
                                          )
                                          (local.set $9
                                           (struct.new $type150
                                            (struct.new $type151
                                             (call $string-new
                                              (i32.const 32)
                                             )
                                            )
                                            (struct.new_default $type152)
                                           )
                                          )
                                          (if
                                           (i64.gt_u
                                            (local.get $1)
                                            (i64.const 1114111)
                                           )
                                           (then
                                            (unreachable)
                                           )
                                          )
                                          (if
                                           (i32.and
                                            (i64.le_u
                                             (local.get $1)
                                             (i64.const 57343)
                                            )
                                            (i64.ge_u
                                             (local.get $1)
                                             (i64.const 55296)
                                            )
                                           )
                                           (then
                                            (unreachable)
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global547)
                                           )
                                          )
                                          (call $function160
                                           (local.get $9)
                                           (i32.wrap_i64
                                            (local.get $1)
                                           )
                                          )
                                          (local.set $4
                                           (call $function170
                                            (local.get $0)
                                            (local.get $9)
                                            (i32.const 0)
                                            (i32.const 1)
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global90)
                                           )
                                          )
                                          (local.set $5
                                           (call $function35
                                            (struct.new $type48
                                             (global.get $string14)
                                             (struct.new $type48
                                              (local.get $4)
                                              (ref.null none)
                                             )
                                            )
                                           )
                                          )
                                          (if
                                           (i32.eqz
                                            (global.get $ready615)
                                           )
                                           (then
                                            (unreachable)
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global615)
                                           )
                                          )
                                          (drop
                                           (ref.as_non_null
                                            (global.get $global595)
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
                                          (local.set $4
                                           (call $function173
                                            (if (result (ref $type18))
                                             (i64.lt_s
                                              (local.tee $1
                                               (i64.extend_i32_u
                                                (struct.get $type18 1
                                                 (local.get $5)
                                                )
                                               )
                                              )
                                              (local.get $1)
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
                                                (local.get $1)
                                                (i64.const 4294967294)
                                               )
                                               (then
                                                (unreachable)
                                               )
                                              )
                                              (call $string-copy
                                               (local.tee $6
                                                (call $string-new
                                                 (i32.wrap_i64
                                                  (local.get $1)
                                                 )
                                                )
                                               )
                                               (i64.const 0)
                                               (local.get $5)
                                               (local.get $1)
                                              )
                                              (local.get $6)
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
                                          (if (result (ref $type159))
                                           (if (result i32)
                                            (local.tee $2
                                             (if (result i32)
                                              (i64.eq
                                               (i64.extend_i32_u
                                                (struct.get $type18 1
                                                 (local.get $4)
                                                )
                                               )
                                               (i64.const 2)
                                              )
                                              (then
                                               (call $function40
                                                (local.get $4)
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
                                            (then
                                             (local.get $2)
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
                                                 (local.get $4)
                                                )
                                               )
                                               (i64.const 5)
                                              )
                                              (then
                                               (call $function40
                                                (local.get $4)
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
                                           )
                                           (then
                                            (struct.new $type160
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
                                            (if (result (ref $type159))
                                             (if (result i32)
                                              (local.tee $2
                                               (if (result i32)
                                                (i64.eq
                                                 (i64.extend_i32_u
                                                  (struct.get $type18 1
                                                   (local.get $4)
                                                  )
                                                 )
                                                 (i64.const 2)
                                                )
                                                (then
                                                 (call $function40
                                                  (local.get $4)
                                                  (global.get $string35)
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
                                               (local.get $2)
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
                                                   (local.get $4)
                                                  )
                                                 )
                                                 (i64.const 6)
                                                )
                                                (then
                                                 (call $function40
                                                  (local.get $4)
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
                                             )
                                             (then
                                              (struct.new $type160
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
                                                (global.get $global365)
                                               )
                                              )
                                              (drop
                                               (ref.as_non_null
                                                (global.get $global317)
                                               )
                                              )
                                              (local.set $3
                                               (call $foreign23
                                                (local.tee $2
                                                 (call $function104
                                                  (local.get $5)
                                                 )
                                                )
                                               )
                                              )
                                              (drop
                                               (ref.as_non_null
                                                (global.get $global362)
                                               )
                                              )
                                              (local.set $8
                                               (call $function117
                                                (local.get $2)
                                                (local.get $3)
                                               )
                                              )
                                              (call $foreign14
                                               (local.get $2)
                                              )
                                              (if (result (ref $type159))
                                               (i32.eq
                                                (struct.get $type121 0
                                                 (local.get $8)
                                                )
                                                (i32.const 1)
                                               )
                                               (then
                                                (struct.new $type160
                                                 (i32.const 0)
                                                 (struct.new $type23
                                                  (i32.const 5)
                                                  (struct.get $type123 1
                                                   (ref.cast (ref $type123)
                                                    (local.get $8)
                                                   )
                                                  )
                                                 )
                                                )
                                               )
                                               (else
                                                (if (result (ref $type166))
                                                 (i32.eq
                                                  (struct.get $type121 0
                                                   (local.get $8)
                                                  )
                                                  (i32.const 2)
                                                 )
                                                 (then
                                                  (struct.new $type166
                                                   (i32.const 6)
                                                   (struct.get $type124 1
                                                    (ref.cast (ref $type124)
                                                     (local.get $8)
                                                    )
                                                   )
                                                  )
                                                 )
                                                 (else
                                                  (struct.new $type166
                                                   (i32.const 6)
                                                   (global.get $string34)
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
                           (global.get $global474)
                          )
                         )
                         (if (result (ref $type166))
                          (if (result i32)
                           (local.tee $2
                            (i64.eq
                             (local.get $1)
                             (i64.const 91)
                            )
                           )
                           (then
                            (local.get $2)
                           )
                           (else
                            (drop
                             (ref.as_non_null
                              (global.get $global474)
                             )
                            )
                            (if (result i32)
                             (local.tee $2
                              (i64.eq
                               (local.get $1)
                               (i64.const 93)
                              )
                             )
                             (then
                              (local.get $2)
                             )
                             (else
                              (drop
                               (ref.as_non_null
                                (global.get $global474)
                               )
                              )
                              (if (result i32)
                               (local.tee $2
                                (i64.eq
                                 (local.get $1)
                                 (i64.const 123)
                                )
                               )
                               (then
                                (local.get $2)
                               )
                               (else
                                (drop
                                 (ref.as_non_null
                                  (global.get $global474)
                                 )
                                )
                                (i64.eq
                                 (local.get $1)
                                 (i64.const 125)
                                )
                               )
                              )
                             )
                            )
                           )
                          )
                          (then
                           (struct.new $type166
                            (i32.const 6)
                            (global.get $string3)
                           )
                          )
                          (else
                           (drop
                            (ref.as_non_null
                             (global.get $global587)
                            )
                           )
                           (drop
                            (ref.as_non_null
                             (global.get $global498)
                            )
                           )
                           (drop
                            (ref.as_non_null
                             (global.get $global61)
                            )
                           )
                           (local.set $9
                            (struct.new $type150
                             (struct.new $type151
                              (call $string-new
                               (i32.const 32)
                              )
                             )
                             (struct.new_default $type152)
                            )
                           )
                           (if
                            (i64.gt_u
                             (local.get $1)
                             (i64.const 1114111)
                            )
                            (then
                             (unreachable)
                            )
                           )
                           (if
                            (i32.and
                             (i64.le_u
                              (local.get $1)
                              (i64.const 57343)
                             )
                             (i64.ge_u
                              (local.get $1)
                              (i64.const 55296)
                             )
                            )
                            (then
                             (unreachable)
                            )
                           )
                           (drop
                            (ref.as_non_null
                             (global.get $global547)
                            )
                           )
                           (call $function160
                            (local.get $9)
                            (i32.wrap_i64
                             (local.get $1)
                            )
                           )
                           (local.set $4
                            (call $function170
                             (local.get $0)
                             (local.get $9)
                             (i32.const 0)
                             (i32.const 1)
                            )
                           )
                           (if
                            (i32.eqz
                             (global.get $ready626)
                            )
                            (then
                             (unreachable)
                            )
                           )
                           (drop
                            (ref.as_non_null
                             (global.get $global626)
                            )
                           )
                           (drop
                            (ref.as_non_null
                             (global.get $global103)
                            )
                           )
                           (return
                            (if (result (ref $type159))
                             (if (result i32)
                              (i64.eq
                               (i64.extend_i32_u
                                (struct.get $type18 1
                                 (local.get $4)
                                )
                               )
                               (i64.const 1)
                              )
                              (then
                               (call $function40
                                (local.get $4)
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
                              (global.get $empty163)
                             )
                             (else
                              (drop
                               (ref.as_non_null
                                (global.get $global365)
                               )
                              )
                              (drop
                               (ref.as_non_null
                                (global.get $global317)
                               )
                              )
                              (local.set $3
                               (call $foreign23
                                (local.tee $2
                                 (call $function104
                                  (local.get $4)
                                 )
                                )
                               )
                              )
                              (drop
                               (ref.as_non_null
                                (global.get $global362)
                               )
                              )
                              (local.set $8
                               (call $function117
                                (local.get $2)
                                (local.get $3)
                               )
                              )
                              (call $foreign14
                               (local.get $2)
                              )
                              (if (result (ref $type159))
                               (i32.eq
                                (struct.get $type121 0
                                 (local.get $8)
                                )
                                (i32.const 1)
                               )
                               (then
                                (struct.new $type160
                                 (i32.const 0)
                                 (struct.new $type23
                                  (i32.const 5)
                                  (struct.get $type123 1
                                   (ref.cast (ref $type123)
                                    (local.get $8)
                                   )
                                  )
                                 )
                                )
                               )
                               (else
                                (if (result (ref $type159))
                                 (i32.eq
                                  (struct.get $type121 0
                                   (local.get $8)
                                  )
                                  (i32.const 2)
                                 )
                                 (then
                                  (struct.new $type166
                                   (i32.const 6)
                                   (struct.get $type124 1
                                    (ref.cast (ref $type124)
                                     (local.get $8)
                                    )
                                   )
                                  )
                                 )
                                 (else
                                  (drop
                                   (ref.as_non_null
                                    (global.get $global325)
                                   )
                                  )
                                  (drop
                                   (ref.as_non_null
                                    (global.get $global317)
                                   )
                                  )
                                  (if (result (ref $type159))
                                   (i32.eq
                                    (call $foreign13
                                     (local.tee $2
                                      (call $function104
                                       (local.get $4)
                                      )
                                     )
                                    )
                                    (block (result i32)
                                     (call $foreign14
                                      (local.get $2)
                                     )
                                     (i32.const 1)
                                    )
                                   )
                                   (then
                                    (drop
                                     (ref.as_non_null
                                      (global.get $global329)
                                     )
                                    )
                                    (drop
                                     (ref.as_non_null
                                      (global.get $global317)
                                     )
                                    )
                                    (struct.new $type160
                                     (i32.const 0)
                                     (struct.new $type21
                                      (i32.const 4)
                                      (struct.new $type22
                                       (call $foreign15
                                        (call $function104
                                         (local.get $4)
                                        )
                                       )
                                      )
                                     )
                                    )
                                   )
                                   (else
                                    (struct.new $type166
                                     (i32.const 6)
                                     (global.get $string39)
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
      )
      (unreachable)
     )
    )
   )
  )
  (if
   (i32.eqz
    (global.get $ready463)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global463)
   )
  )
  (return_call $function137
   (local.get $0)
  )
 )
