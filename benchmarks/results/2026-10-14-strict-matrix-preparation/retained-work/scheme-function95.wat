(func $function95 (type $66) (param $0 i64) (param $1 (ref $type33)) (result (ref $type12))
  (local $2 (ref $type12))
  (local $3 (ref $type12))
  (local $4 i32)
  (if
   (i32.eqz
    (global.get $ready218)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global218)
   )
  )
  (local.set $3
   (if (result (ref $type12))
    (if (result i32)
     (local.tee $4
      (i64.lt_s
       (local.get $0)
       (i64.const 0)
      )
     )
     (then
      (local.get $4)
     )
     (else
      (i64.gt_s
       (local.get $0)
       (i64.const 4294967295)
      )
     )
    )
    (then
     (unreachable)
    )
    (else
     (if (result (ref $type12))
      (i64.eqz
       (local.get $0)
      )
      (then
       (array.new_fixed $type12 0)
      )
      (else
       (if
        (i32.eqz
         (global.get $ready55)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global55)
        )
       )
       (if
        (i64.gt_u
         (local.get $0)
         (i64.const 4294967295)
        )
        (then
         (unreachable)
        )
       )
       (local.set $2
        (array.new_default $type12
         (i32.wrap_i64
          (local.get $0)
         )
        )
       )
       (if (result (ref $type12))
        (i64.eq
         (local.get $0)
         (i64.const 1)
        )
        (then
         (local.get $2)
        )
        (else
         (if
          (i32.eqz
           (global.get $ready55)
          )
          (then
           (unreachable)
          )
         )
         (drop
          (ref.as_non_null
           (global.get $global55)
          )
         )
         (array.set $type12
          (local.get $2)
          (i32.const 1)
          (i64.const 0)
         )
         (if (result (ref $type12))
          (i64.eq
           (local.get $0)
           (i64.const 2)
          )
          (then
           (local.get $2)
          )
          (else
           (if
            (i32.eqz
             (global.get $ready55)
            )
            (then
             (unreachable)
            )
           )
           (drop
            (ref.as_non_null
             (global.get $global55)
            )
           )
           (array.set $type12
            (local.get $2)
            (i32.const 2)
            (i64.const 0)
           )
           (if (result (ref $type12))
            (i64.eq
             (local.get $0)
             (i64.const 3)
            )
            (then
             (local.get $2)
            )
            (else
             (if
              (i32.eqz
               (global.get $ready55)
              )
              (then
               (unreachable)
              )
             )
             (drop
              (ref.as_non_null
               (global.get $global55)
              )
             )
             (array.set $type12
              (local.get $2)
              (i32.const 3)
              (i64.const 0)
             )
             (if (result (ref $type12))
              (i64.eq
               (local.get $0)
               (i64.const 4)
              )
              (then
               (local.get $2)
              )
              (else
               (if
                (i32.eqz
                 (global.get $ready55)
                )
                (then
                 (unreachable)
                )
               )
               (drop
                (ref.as_non_null
                 (global.get $global55)
                )
               )
               (array.set $type12
                (local.get $2)
                (i32.const 4)
                (i64.const 0)
               )
               (if (result (ref $type12))
                (i64.eq
                 (local.get $0)
                 (i64.const 5)
                )
                (then
                 (local.get $2)
                )
                (else
                 (if
                  (i32.eqz
                   (global.get $ready55)
                  )
                  (then
                   (unreachable)
                  )
                 )
                 (drop
                  (ref.as_non_null
                   (global.get $global55)
                  )
                 )
                 (array.set $type12
                  (local.get $2)
                  (i32.const 5)
                  (i64.const 0)
                 )
                 (if (result (ref $type12))
                  (i64.eq
                   (local.get $0)
                   (i64.const 6)
                  )
                  (then
                   (local.get $2)
                  )
                  (else
                   (if
                    (i32.eqz
                     (global.get $ready55)
                    )
                    (then
                     (unreachable)
                    )
                   )
                   (drop
                    (ref.as_non_null
                     (global.get $global55)
                    )
                   )
                   (array.set $type12
                    (local.get $2)
                    (i32.const 6)
                    (i64.const 0)
                   )
                   (if (result (ref $type12))
                    (i64.eq
                     (local.get $0)
                     (i64.const 7)
                    )
                    (then
                     (local.get $2)
                    )
                    (else
                     (if
                      (i32.eqz
                       (global.get $ready55)
                      )
                      (then
                       (unreachable)
                      )
                     )
                     (drop
                      (ref.as_non_null
                       (global.get $global55)
                      )
                     )
                     (array.set $type12
                      (local.get $2)
                      (i32.const 7)
                      (i64.const 0)
                     )
                     (if (result (ref $type12))
                      (i64.eq
                       (local.get $0)
                       (i64.const 8)
                      )
                      (then
                       (local.get $2)
                      )
                      (else
                       (if
                        (i32.eqz
                         (global.get $ready55)
                        )
                        (then
                         (unreachable)
                        )
                       )
                       (drop
                        (ref.as_non_null
                         (global.get $global55)
                        )
                       )
                       (array.set $type12
                        (local.get $2)
                        (i32.const 8)
                        (i64.const 0)
                       )
                       (if (result (ref $type12))
                        (i64.eq
                         (local.get $0)
                         (i64.const 9)
                        )
                        (then
                         (local.get $2)
                        )
                        (else
                         (if
                          (i32.eqz
                           (global.get $ready55)
                          )
                          (then
                           (unreachable)
                          )
                         )
                         (drop
                          (ref.as_non_null
                           (global.get $global55)
                          )
                         )
                         (array.set $type12
                          (local.get $2)
                          (i32.const 9)
                          (i64.const 0)
                         )
                         (call $function77
                          (local.get $0)
                          (local.get $2)
                          (i32.const 0)
                          (i32.const 1)
                          (i64.const 10)
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
  (drop
   (if (result i32)
    (i64.eqz
     (local.get $0)
    )
    (then
     (i32.const 0)
    )
    (else
     (array.set $type12
      (local.get $3)
      (i32.const 0)
      (call_ref $call33
       (struct.get $type33 1
        (local.get $1)
       )
       (i64.const 0)
       (struct.get $type33 0
        (local.get $1)
       )
      )
     )
     (if (result i32)
      (i64.eq
       (local.get $0)
       (i64.const 1)
      )
      (then
       (i32.const 0)
      )
      (else
       (array.set $type12
        (local.get $3)
        (i32.const 1)
        (call_ref $call33
         (struct.get $type33 1
          (local.get $1)
         )
         (i64.const 1)
         (struct.get $type33 0
          (local.get $1)
         )
        )
       )
       (if (result i32)
        (i64.eq
         (local.get $0)
         (i64.const 2)
        )
        (then
         (i32.const 0)
        )
        (else
         (array.set $type12
          (local.get $3)
          (i32.const 2)
          (call_ref $call33
           (struct.get $type33 1
            (local.get $1)
           )
           (i64.const 2)
           (struct.get $type33 0
            (local.get $1)
           )
          )
         )
         (if (result i32)
          (i64.eq
           (local.get $0)
           (i64.const 3)
          )
          (then
           (i32.const 0)
          )
          (else
           (array.set $type12
            (local.get $3)
            (i32.const 3)
            (call_ref $call33
             (struct.get $type33 1
              (local.get $1)
             )
             (i64.const 3)
             (struct.get $type33 0
              (local.get $1)
             )
            )
           )
           (if (result i32)
            (i64.eq
             (local.get $0)
             (i64.const 4)
            )
            (then
             (i32.const 0)
            )
            (else
             (array.set $type12
              (local.get $3)
              (i32.const 4)
              (call_ref $call33
               (struct.get $type33 1
                (local.get $1)
               )
               (i64.const 4)
               (struct.get $type33 0
                (local.get $1)
               )
              )
             )
             (if (result i32)
              (i64.eq
               (local.get $0)
               (i64.const 5)
              )
              (then
               (i32.const 0)
              )
              (else
               (array.set $type12
                (local.get $3)
                (i32.const 5)
                (call_ref $call33
                 (struct.get $type33 1
                  (local.get $1)
                 )
                 (i64.const 5)
                 (struct.get $type33 0
                  (local.get $1)
                 )
                )
               )
               (if (result i32)
                (i64.eq
                 (local.get $0)
                 (i64.const 6)
                )
                (then
                 (i32.const 0)
                )
                (else
                 (array.set $type12
                  (local.get $3)
                  (i32.const 6)
                  (call_ref $call33
                   (struct.get $type33 1
                    (local.get $1)
                   )
                   (i64.const 6)
                   (struct.get $type33 0
                    (local.get $1)
                   )
                  )
                 )
                 (if (result i32)
                  (i64.eq
                   (local.get $0)
                   (i64.const 7)
                  )
                  (then
                   (i32.const 0)
                  )
                  (else
                   (array.set $type12
                    (local.get $3)
                    (i32.const 7)
                    (call_ref $call33
                     (struct.get $type33 1
                      (local.get $1)
                     )
                     (i64.const 7)
                     (struct.get $type33 0
                      (local.get $1)
                     )
                    )
                   )
                   (if (result i32)
                    (i64.eq
                     (local.get $0)
                     (i64.const 8)
                    )
                    (then
                     (i32.const 0)
                    )
                    (else
                     (array.set $type12
                      (local.get $3)
                      (i32.const 8)
                      (call_ref $call33
                       (struct.get $type33 1
                        (local.get $1)
                       )
                       (i64.const 8)
                       (struct.get $type33 0
                        (local.get $1)
                       )
                      )
                     )
                     (if (result i32)
                      (i64.eq
                       (local.get $0)
                       (i64.const 9)
                      )
                      (then
                       (i32.const 0)
                      )
                      (else
                       (array.set $type12
                        (local.get $3)
                        (i32.const 9)
                        (call_ref $call33
                         (struct.get $type33 1
                          (local.get $1)
                         )
                         (i64.const 9)
                         (struct.get $type33 0
                          (local.get $1)
                         )
                        )
                       )
                       (call $function96
                        (local.get $0)
                        (local.get $1)
                        (local.get $3)
                        (i32.const 0)
                        (i32.const 1)
                        (i64.const 10)
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
  (local.get $3)
 )
