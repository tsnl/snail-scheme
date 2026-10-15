(func $function52 (type $call68) (param $0 (ref null $type32)) (param $1 (ref null $type32)) (result i32)
  (local $2 (ref null $type30))
  (local $3 (ref null $type30))
  (local $scratch (ref null $type30))
  (local $scratch_5 (ref null $type32))
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
       (struct.get $type32 0
        (local.get $0)
       )
      )
      (local.set $2
       (struct.get $type32 0
        (local.get $1)
       )
      )
      (if
       (i32.eqz
        (global.get $ready139)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global139)
       )
      )
      (if (result i32)
       (if (result i32)
        (ref.is_null
         (local.get $3)
        )
        (then
         (ref.is_null
          (local.get $2)
         )
        )
        (else
         (if (result i32)
          (ref.is_null
           (local.get $2)
          )
          (then
           (i32.const 0)
          )
          (else
           (if (result i32)
            (i64.eq
             (struct.get $type30 0
              (local.get $3)
             )
             (struct.get $type30 0
              (local.get $2)
             )
            )
            (then
             (local.set $3
              (struct.get $type30 1
               (local.get $3)
              )
             )
             (local.set $2
              (struct.get $type30 1
               (local.get $2)
              )
             )
             (if
              (i32.eqz
               (global.get $ready139)
              )
              (then
               (unreachable)
              )
             )
             (drop
              (ref.as_non_null
               (global.get $global139)
              )
             )
             (if (result i32)
              (ref.is_null
               (local.get $3)
              )
              (then
               (ref.is_null
                (local.get $2)
               )
              )
              (else
               (if (result i32)
                (ref.is_null
                 (local.get $2)
                )
                (then
                 (i32.const 0)
                )
                (else
                 (if (result i32)
                  (i64.eq
                   (struct.get $type30 0
                    (local.get $3)
                   )
                   (struct.get $type30 0
                    (local.get $2)
                   )
                  )
                  (then
                   (local.set $3
                    (struct.get $type30 1
                     (local.get $3)
                    )
                   )
                   (local.set $2
                    (struct.get $type30 1
                     (local.get $2)
                    )
                   )
                   (if
                    (i32.eqz
                     (global.get $ready139)
                    )
                    (then
                     (unreachable)
                    )
                   )
                   (drop
                    (ref.as_non_null
                     (global.get $global139)
                    )
                   )
                   (if (result i32)
                    (ref.is_null
                     (local.get $3)
                    )
                    (then
                     (ref.is_null
                      (local.get $2)
                     )
                    )
                    (else
                     (if (result i32)
                      (ref.is_null
                       (local.get $2)
                      )
                      (then
                       (i32.const 0)
                      )
                      (else
                       (if (result i32)
                        (i64.eq
                         (struct.get $type30 0
                          (local.get $3)
                         )
                         (struct.get $type30 0
                          (local.get $2)
                         )
                        )
                        (then
                         (local.set $3
                          (struct.get $type30 1
                           (local.get $3)
                          )
                         )
                         (local.set $2
                          (struct.get $type30 1
                           (local.get $2)
                          )
                         )
                         (if
                          (i32.eqz
                           (global.get $ready139)
                          )
                          (then
                           (unreachable)
                          )
                         )
                         (drop
                          (ref.as_non_null
                           (global.get $global139)
                          )
                         )
                         (if (result i32)
                          (ref.is_null
                           (local.get $3)
                          )
                          (then
                           (ref.is_null
                            (local.get $2)
                           )
                          )
                          (else
                           (if (result i32)
                            (ref.is_null
                             (local.get $2)
                            )
                            (then
                             (i32.const 0)
                            )
                            (else
                             (if (result i32)
                              (i64.eq
                               (struct.get $type30 0
                                (local.get $3)
                               )
                               (struct.get $type30 0
                                (local.get $2)
                               )
                              )
                              (then
                               (local.set $3
                                (struct.get $type30 1
                                 (local.get $3)
                                )
                               )
                               (local.set $2
                                (struct.get $type30 1
                                 (local.get $2)
                                )
                               )
                               (if
                                (i32.eqz
                                 (global.get $ready139)
                                )
                                (then
                                 (unreachable)
                                )
                               )
                               (drop
                                (ref.as_non_null
                                 (global.get $global139)
                                )
                               )
                               (if (result i32)
                                (ref.is_null
                                 (local.get $3)
                                )
                                (then
                                 (ref.is_null
                                  (local.get $2)
                                 )
                                )
                                (else
                                 (if (result i32)
                                  (ref.is_null
                                   (local.get $2)
                                  )
                                  (then
                                   (i32.const 0)
                                  )
                                  (else
                                   (if (result i32)
                                    (i64.eq
                                     (struct.get $type30 0
                                      (local.get $3)
                                     )
                                     (struct.get $type30 0
                                      (local.get $2)
                                     )
                                    )
                                    (then
                                     (local.set $3
                                      (struct.get $type30 1
                                       (local.get $3)
                                      )
                                     )
                                     (local.set $2
                                      (struct.get $type30 1
                                       (local.get $2)
                                      )
                                     )
                                     (if
                                      (i32.eqz
                                       (global.get $ready139)
                                      )
                                      (then
                                       (unreachable)
                                      )
                                     )
                                     (drop
                                      (ref.as_non_null
                                       (global.get $global139)
                                      )
                                     )
                                     (if (result i32)
                                      (ref.is_null
                                       (local.get $3)
                                      )
                                      (then
                                       (ref.is_null
                                        (local.get $2)
                                       )
                                      )
                                      (else
                                       (if (result i32)
                                        (ref.is_null
                                         (local.get $2)
                                        )
                                        (then
                                         (i32.const 0)
                                        )
                                        (else
                                         (if (result i32)
                                          (i64.eq
                                           (struct.get $type30 0
                                            (local.get $3)
                                           )
                                           (struct.get $type30 0
                                            (local.get $2)
                                           )
                                          )
                                          (then
                                           (local.set $3
                                            (struct.get $type30 1
                                             (local.get $3)
                                            )
                                           )
                                           (local.set $2
                                            (struct.get $type30 1
                                             (local.get $2)
                                            )
                                           )
                                           (if
                                            (i32.eqz
                                             (global.get $ready139)
                                            )
                                            (then
                                             (unreachable)
                                            )
                                           )
                                           (drop
                                            (ref.as_non_null
                                             (global.get $global139)
                                            )
                                           )
                                           (if (result i32)
                                            (ref.is_null
                                             (local.get $3)
                                            )
                                            (then
                                             (ref.is_null
                                              (local.get $2)
                                             )
                                            )
                                            (else
                                             (if (result i32)
                                              (ref.is_null
                                               (local.get $2)
                                              )
                                              (then
                                               (i32.const 0)
                                              )
                                              (else
                                               (if (result i32)
                                                (i64.eq
                                                 (struct.get $type30 0
                                                  (local.get $3)
                                                 )
                                                 (struct.get $type30 0
                                                  (local.get $2)
                                                 )
                                                )
                                                (then
                                                 (local.set $3
                                                  (struct.get $type30 1
                                                   (local.get $3)
                                                  )
                                                 )
                                                 (local.set $2
                                                  (struct.get $type30 1
                                                   (local.get $2)
                                                  )
                                                 )
                                                 (if
                                                  (i32.eqz
                                                   (global.get $ready139)
                                                  )
                                                  (then
                                                   (unreachable)
                                                  )
                                                 )
                                                 (drop
                                                  (ref.as_non_null
                                                   (global.get $global139)
                                                  )
                                                 )
                                                 (if (result i32)
                                                  (ref.is_null
                                                   (local.get $3)
                                                  )
                                                  (then
                                                   (ref.is_null
                                                    (local.get $2)
                                                   )
                                                  )
                                                  (else
                                                   (if (result i32)
                                                    (ref.is_null
                                                     (local.get $2)
                                                    )
                                                    (then
                                                     (i32.const 0)
                                                    )
                                                    (else
                                                     (if (result i32)
                                                      (i64.eq
                                                       (struct.get $type30 0
                                                        (local.get $3)
                                                       )
                                                       (struct.get $type30 0
                                                        (local.get $2)
                                                       )
                                                      )
                                                      (then
                                                       (local.set $3
                                                        (struct.get $type30 1
                                                         (local.get $3)
                                                        )
                                                       )
                                                       (local.set $2
                                                        (struct.get $type30 1
                                                         (local.get $2)
                                                        )
                                                       )
                                                       (if
                                                        (i32.eqz
                                                         (global.get $ready139)
                                                        )
                                                        (then
                                                         (unreachable)
                                                        )
                                                       )
                                                       (drop
                                                        (ref.as_non_null
                                                         (global.get $global139)
                                                        )
                                                       )
                                                       (if (result i32)
                                                        (ref.is_null
                                                         (local.get $3)
                                                        )
                                                        (then
                                                         (ref.is_null
                                                          (local.get $2)
                                                         )
                                                        )
                                                        (else
                                                         (if (result i32)
                                                          (ref.is_null
                                                           (local.get $2)
                                                          )
                                                          (then
                                                           (i32.const 0)
                                                          )
                                                          (else
                                                           (if (result i32)
                                                            (i64.eq
                                                             (struct.get $type30 0
                                                              (local.get $3)
                                                             )
                                                             (struct.get $type30 0
                                                              (local.get $2)
                                                             )
                                                            )
                                                            (then
                                                             (local.set $3
                                                              (struct.get $type30 1
                                                               (local.get $3)
                                                              )
                                                             )
                                                             (local.set $2
                                                              (struct.get $type30 1
                                                               (local.get $2)
                                                              )
                                                             )
                                                             (if
                                                              (i32.eqz
                                                               (global.get $ready139)
                                                              )
                                                              (then
                                                               (unreachable)
                                                              )
                                                             )
                                                             (drop
                                                              (ref.as_non_null
                                                               (global.get $global139)
                                                              )
                                                             )
                                                             (if (result i32)
                                                              (ref.is_null
                                                               (local.get $3)
                                                              )
                                                              (then
                                                               (ref.is_null
                                                                (local.get $2)
                                                               )
                                                              )
                                                              (else
                                                               (if (result i32)
                                                                (ref.is_null
                                                                 (local.get $2)
                                                                )
                                                                (then
                                                                 (i32.const 0)
                                                                )
                                                                (else
                                                                 (if (result i32)
                                                                  (i64.eq
                                                                   (struct.get $type30 0
                                                                    (local.get $3)
                                                                   )
                                                                   (struct.get $type30 0
                                                                    (local.get $2)
                                                                   )
                                                                  )
                                                                  (then
                                                                   (call $function51
                                                                    (struct.get $type30 1
                                                                     (local.get $3)
                                                                    )
                                                                    (block (result (ref null $type30))
                                                                     (local.set $scratch
                                                                      (struct.get $type30 1
                                                                       (local.get $2)
                                                                      )
                                                                     )
                                                                     (if
                                                                      (i32.eqz
                                                                       (global.get $ready139)
                                                                      )
                                                                      (then
                                                                       (unreachable)
                                                                      )
                                                                     )
                                                                     (drop
                                                                      (ref.as_non_null
                                                                       (global.get $global139)
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
                                                               )
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
                                                      (else
                                                       (i32.const 0)
                                                      )
                                                     )
                                                    )
                                                   )
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
                                          (else
                                           (i32.const 0)
                                          )
                                         )
                                        )
                                       )
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
                              (else
                               (i32.const 0)
                              )
                             )
                            )
                           )
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
                  (else
                   (i32.const 0)
                  )
                 )
                )
               )
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
       (then
        (return_call $function52
         (struct.get $type32 1
          (local.get $0)
         )
         (block (result (ref null $type32))
          (local.set $scratch_5
           (struct.get $type32 1
            (local.get $1)
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
          (local.get $scratch_5)
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
