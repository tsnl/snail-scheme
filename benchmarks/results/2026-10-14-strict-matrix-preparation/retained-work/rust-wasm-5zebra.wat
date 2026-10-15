(func $_ZN6matrix5zebra17hfa0b4bd4996b012aE (param $0 i32) (param $1 i32) (param $2 i32) (param $3 i32) (param $4 i32) (result i32)
  (local $5 i32)
  (local $6 i32)
  (local $7 i32)
  (local $8 i32)
  (local $9 i32)
  (local $10 i32)
  (local $11 i32)
  (local $12 i32)
  (local $13 i32)
  (local $14 i32)
  (local $15 i32)
  (local $16 i32)
  (local $17 i32)
  (local $18 i32)
  (local $19 i32)
  (local $20 i32)
  (local $21 i32)
  (local $22 i32)
  (local $23 i32)
  (local $24 i32)
  (local $25 i32)
  (local $26 i32)
  (local $27 i32)
  (local $28 i32)
  (local $29 i32)
  (local $30 i32)
  (local $31 i32)
  (local $32 i32)
  (local $33 i32)
  (local $34 i32)
  (local $35 i32)
  (local $36 i32)
  (local $37 i32)
  (local $38 i64)
  (local $39 i64)
  (local $40 i64)
  (local $scratch i32)
  (local $scratch_42 i32)
  (local $scratch_43 i32)
  (local $scratch_44 i32)
  (global.set $__stack_pointer
   (local.tee $5
    (i32.sub
     (global.get $__stack_pointer)
     (i32.const 80)
    )
   )
  )
  (local.set $7
   (i32.const 1)
  )
  (block $block1
   (block $block
    (br_if $block
     (i32.ne
      (i32.load
       (local.get $0)
      )
      (i32.const 1)
     )
    )
    (br_if $block1
     (i32.eqz
      (local.tee $2
       (i32.load
        (local.get $2)
       )
      )
     )
    )
    (local.set $32
     (i32.add
      (local.get $2)
      (i32.const 12)
     )
    )
    (local.set $33
     (i32.add
      (local.get $3)
      (i32.mul
       (local.get $4)
       (i32.const 12)
      )
     )
    )
    (local.set $34
     (i32.add
      (local.get $2)
      (i32.const 8)
     )
    )
    (local.set $35
     (i32.add
      (local.get $5)
      (i32.const 24)
     )
    )
    (local.set $30
     (i32.add
      (local.get $5)
      (i32.const 12)
     )
    )
    (loop $label11
     (i32.store offset=12
      (local.get $5)
      (local.tee $11
       (i32.load offset=8
        (local.get $0)
       )
      )
     )
     (i32.store offset=8
      (local.get $5)
      (local.tee $12
       (i32.load offset=4
        (local.get $0)
       )
      )
     )
     (i64.store offset=32
      (local.get $5)
      (i64.const -1)
     )
     (i64.store offset=24
      (local.get $5)
      (i64.const 1)
     )
     (i32.store offset=20
      (local.get $5)
      (i32.const 2)
     )
     (block $block33
      (if
       (local.get $12)
       (then
        (local.set $7
         (i32.const 0)
        )
        (loop $label10
         (local.set $23
          (i32.const 1)
         )
         (i32.store offset=16
          (local.get $5)
          (local.tee $36
           (i32.add
            (local.get $7)
            (i32.const 1)
           )
          )
         )
         (local.set $38
          (i64.load
           (i32.add
            (local.get $35)
            (i32.shl
             (local.get $7)
             (i32.const 3)
            )
           )
          )
         )
         (i32.store offset=76
          (local.get $5)
          (i32.const 0)
         )
         (i64.store offset=68 align=4
          (local.get $5)
          (i64.const 34359738368)
         )
         (block $block21
          (local.set $8
           (block $block4 (result i32)
            (block $block20
             (block $block9
              (block $block3
               (local.set $26
                (block $block2 (result i32)
                 (if
                  (i32.eqz
                   (local.tee $2
                    (i32.load offset=8
                     (local.get $12)
                    )
                   )
                  )
                  (then
                   (local.set $7
                    (i32.const 0)
                   )
                   (br $block2
                    (i32.const 8)
                   )
                  )
                 )
                 (local.set $39
                  (i64.sub
                   (i64.const 0)
                   (local.get $38)
                  )
                 )
                 (local.set $8
                  (i32.const 8)
                 )
                 (local.set $7
                  (i32.const 0)
                 )
                 (local.set $6
                  (i32.const 0)
                 )
                 (local.set $9
                  (local.get $1)
                 )
                 (loop $label
                  (br_if $block3
                   (i32.eqz
                    (local.tee $9
                     (i32.load
                      (local.get $9)
                     )
                    )
                   )
                  )
                  (local.set $40
                   (select
                    (local.get $38)
                    (local.get $39)
                    (i64.eq
                     (i64.load offset=8
                      (local.get $9)
                     )
                     (i64.load offset=8
                      (local.get $2)
                     )
                    )
                   )
                  )
                  (if
                   (i32.eq
                    (i32.load offset=68
                     (local.get $5)
                    )
                    (local.get $7)
                   )
                   (then
                    (call $_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17hc4152392a39fc886E
                     (i32.add
                      (local.get $5)
                      (i32.const 68)
                     )
                    )
                    (local.set $8
                     (i32.load offset=72
                      (local.get $5)
                     )
                    )
                   )
                  )
                  (i64.store
                   (i32.add
                    (local.get $6)
                    (local.get $8)
                   )
                   (local.get $40)
                  )
                  (i32.store offset=76
                   (local.get $5)
                   (local.tee $7
                    (i32.add
                     (local.get $7)
                     (i32.const 1)
                    )
                   )
                  )
                  (local.set $6
                   (i32.add
                    (local.get $6)
                    (i32.const 8)
                   )
                  )
                  (local.set $9
                   (i32.add
                    (local.get $9)
                    (i32.const 16)
                   )
                  )
                  (br_if $label
                   (local.tee $2
                    (i32.load offset=16
                     (local.get $2)
                    )
                   )
                  )
                 )
                 (local.set $23
                  (i32.eqz
                   (i32.load offset=68
                    (local.get $5)
                   )
                  )
                 )
                 (i32.load offset=72
                  (local.get $5)
                 )
                )
               )
               (i32.store offset=52
                (local.get $5)
                (i32.const 0)
               )
               (i64.store offset=44 align=4
                (local.get $5)
                (i64.const 17179869184)
               )
               (drop
                (br_if $block4
                 (i32.const 0)
                 (i32.eqz
                  (local.get $4)
                 )
                )
               )
               (local.set $24
                (local.get $34)
               )
               (local.set $25
                (local.get $3)
               )
               (loop $label5
                (local.set $9
                 (i32.const 0)
                )
                (i32.store offset=64
                 (local.get $5)
                 (i32.const 0)
                )
                (i64.store offset=56 align=4
                 (local.get $5)
                 (i64.const 17179869184)
                )
                (i32.store offset=76
                 (local.get $5)
                 (i32.const 0)
                )
                (i64.store offset=68 align=4
                 (local.get $5)
                 (i64.const 17179869184)
                )
                (local.set $31
                 (i32.const 1)
                )
                (block $block18
                 (block $block17
                  (block $block11
                   (block $block12
                    (block $block5
                     (if
                      (i32.eqz
                       (local.tee $2
                        (i32.load offset=8
                         (local.get $25)
                        )
                       )
                      )
                      (then
                       (local.set $10
                        (i32.const 4)
                       )
                       (local.set $15
                        (i32.const 4)
                       )
                       (br $block5)
                      )
                     )
                     (local.set $8
                      (i32.shl
                       (local.get $2)
                       (i32.const 2)
                      )
                     )
                     (local.set $2
                      (i32.load offset=4
                       (local.get $25)
                      )
                     )
                     (local.set $15
                      (i32.const 4)
                     )
                     (loop $label1
                      (block $block10
                       (block $block6
                        (block $block8
                         (block $block7
                          (if
                           (i32.gt_u
                            (local.get $7)
                            (local.tee $6
                             (i32.load
                              (local.get $2)
                             )
                            )
                           )
                           (then
                            (br_if $block6
                             (i64.ne
                              (i64.load
                               (i32.add
                                (local.get $26)
                                (i32.shl
                                 (local.get $6)
                                 (i32.const 3)
                                )
                               )
                              )
                              (i64.const 1)
                             )
                            )
                            (br_if $block7
                             (i32.eqz
                              (local.tee $16
                               (i32.load
                                (local.get $24)
                               )
                              )
                             )
                            )
                            (br_if $block8
                             (i64.eq
                              (i64.load offset=8
                               (local.get $16)
                              )
                              (i64.const 1)
                             )
                            )
                            (local.set $8
                             (i32.const -2147483648)
                            )
                            (br $block9)
                           )
                          )
                          (call $_RNvNtCsdHhIpgkcIfN_4core9panicking18panic_bounds_check
                           (local.get $6)
                           (local.get $7)
                           (i32.const 1052188)
                          )
                          (unreachable)
                         )
                         (call $_RNvNtCsdHhIpgkcIfN_4core6option13unwrap_failed
                          (i32.const 1052204)
                         )
                         (unreachable)
                        )
                        (if
                         (i32.eq
                          (local.tee $10
                           (i32.load offset=64
                            (local.get $5)
                           )
                          )
                          (i32.load offset=56
                           (local.get $5)
                          )
                         )
                         (then
                          (call $_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h1517403c739da271E
                           (i32.add
                            (local.get $5)
                            (i32.const 56)
                           )
                          )
                         )
                        )
                        (local.set $24
                         (i32.add
                          (local.get $16)
                          (i32.const 16)
                         )
                        )
                        (i32.store
                         (i32.add
                          (i32.load offset=60
                           (local.get $5)
                          )
                          (i32.shl
                           (local.get $10)
                           (i32.const 2)
                          )
                         )
                         (local.get $6)
                        )
                        (i32.store offset=64
                         (local.get $5)
                         (i32.add
                          (local.get $10)
                          (i32.const 1)
                         )
                        )
                        (br $block10)
                       )
                       (if
                        (i32.eq
                         (i32.load offset=68
                          (local.get $5)
                         )
                         (local.get $9)
                        )
                        (then
                         (call $_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h1517403c739da271E
                          (i32.add
                           (local.get $5)
                           (i32.const 68)
                          )
                         )
                         (local.set $15
                          (i32.load offset=72
                           (local.get $5)
                          )
                         )
                        )
                       )
                       (i32.store
                        (i32.add
                         (local.get $15)
                         (i32.shl
                          (local.get $9)
                          (i32.const 2)
                         )
                        )
                        (local.get $6)
                       )
                       (i32.store offset=76
                        (local.get $5)
                        (local.tee $9
                         (i32.add
                          (local.get $9)
                          (i32.const 1)
                         )
                        )
                       )
                      )
                      (local.set $2
                       (i32.add
                        (local.get $2)
                        (i32.const 4)
                       )
                      )
                      (br_if $label1
                       (local.tee $8
                        (i32.sub
                         (local.get $8)
                         (i32.const 4)
                        )
                       )
                      )
                     )
                     (local.set $10
                      (i32.add
                       (local.tee $15
                        (i32.load offset=72
                         (local.get $5)
                        )
                       )
                       (local.tee $6
                        (i32.shl
                         (local.get $9)
                         (i32.const 2)
                        )
                       )
                      )
                     )
                     (if
                      (i32.eqz
                       (local.get $9)
                      )
                      (then
                       (local.set $9
                        (i32.const 0)
                       )
                       (br $block5)
                      )
                     )
                     (loop $label2
                      (br_if $block11
                       (i32.eqz
                        (local.tee $2
                         (i32.load
                          (local.get $24)
                         )
                        )
                       )
                      )
                      (br_if $block12
                       (i64.eq
                        (i64.load offset=8
                         (local.get $2)
                        )
                        (i64.const 1)
                       )
                      )
                      (local.set $24
                       (i32.add
                        (local.get $2)
                        (i32.const 16)
                       )
                      )
                      (br_if $label2
                       (local.tee $6
                        (i32.sub
                         (local.get $6)
                         (i32.const 4)
                        )
                       )
                      )
                     )
                     (local.set $31
                      (i32.const 0)
                     )
                    )
                    (local.set $16
                     (i32.load offset=60
                      (local.get $5)
                     )
                    )
                    (block $block13
                     (br_if $block13
                      (i32.eqz
                       (local.tee $2
                        (i32.shr_u
                         (local.tee $27
                          (i32.load offset=64
                           (local.get $5)
                          )
                         )
                         (i32.const 1)
                        )
                       )
                      )
                     )
                     (local.set $13
                      (i32.add
                       (local.get $16)
                       (i32.shl
                        (local.get $27)
                        (i32.const 2)
                       )
                      )
                     )
                     (local.set $6
                      (i32.const 0)
                     )
                     (if
                      (i32.ne
                       (local.get $2)
                       (i32.const 1)
                      )
                      (then
                       (br_if $block13
                        (i32.eqz
                         (block (result i32)
                          (local.set $scratch_42
                           (i32.and
                            (local.get $2)
                            (i32.const 1)
                           )
                          )
                          (block $block14
                           (if
                            (local.tee $2
                             (i32.shr_u
                              (i32.sub
                               (local.get $2)
                               (i32.const 2)
                              )
                              (i32.const 1)
                             )
                            )
                            (then
                             (br_if $block14
                              (i32.eqz
                               (block (result i32)
                                (local.set $scratch
                                 (i32.and
                                  (local.tee $2
                                   (i32.add
                                    (local.get $2)
                                    (i32.const 1)
                                   )
                                  )
                                  (i32.const 1)
                                 )
                                )
                                (local.set $20
                                 (i32.and
                                  (local.get $2)
                                  (i32.const 2147483646)
                                 )
                                )
                                (local.set $8
                                 (i32.sub
                                  (local.get $13)
                                  (i32.const 4)
                                 )
                                )
                                (local.set $2
                                 (local.get $16)
                                )
                                (loop $label3
                                 (local.set $19
                                  (i32.load
                                   (local.get $8)
                                  )
                                 )
                                 (i32.store
                                  (local.get $8)
                                  (i32.load
                                   (local.get $2)
                                  )
                                 )
                                 (local.set $28
                                  (i32.load
                                   (local.tee $14
                                    (i32.add
                                     (local.get $13)
                                     (i32.shl
                                      (i32.xor
                                       (local.get $6)
                                       (i32.const 1073741822)
                                      )
                                      (i32.const 2)
                                     )
                                    )
                                   )
                                  )
                                 )
                                 (i32.store
                                  (local.get $14)
                                  (i32.load
                                   (local.tee $14
                                    (i32.add
                                     (local.get $2)
                                     (i32.const 4)
                                    )
                                   )
                                  )
                                 )
                                 (local.set $37
                                  (i32.load
                                   (local.tee $29
                                    (i32.add
                                     (local.get $13)
                                     (i32.shl
                                      (i32.xor
                                       (local.get $6)
                                       (i32.const 1073741821)
                                      )
                                      (i32.const 2)
                                     )
                                    )
                                   )
                                  )
                                 )
                                 (i32.store
                                  (local.get $29)
                                  (i32.load
                                   (local.tee $29
                                    (i32.add
                                     (local.get $2)
                                     (i32.const 8)
                                    )
                                   )
                                  )
                                 )
                                 (i32.store
                                  (local.get $2)
                                  (local.get $19)
                                 )
                                 (i32.store
                                  (local.get $14)
                                  (local.get $28)
                                 )
                                 (i32.store
                                  (local.get $29)
                                  (local.get $37)
                                 )
                                 (local.set $14
                                  (i32.load
                                   (local.tee $19
                                    (i32.add
                                     (local.get $13)
                                     (i32.shl
                                      (i32.xor
                                       (local.get $6)
                                       (i32.const 1073741820)
                                      )
                                      (i32.const 2)
                                     )
                                    )
                                   )
                                  )
                                 )
                                 (i32.store
                                  (local.get $19)
                                  (i32.load
                                   (local.tee $19
                                    (i32.add
                                     (local.get $2)
                                     (i32.const 12)
                                    )
                                   )
                                  )
                                 )
                                 (i32.store
                                  (local.get $19)
                                  (local.get $14)
                                 )
                                 (local.set $8
                                  (i32.sub
                                   (local.get $8)
                                   (i32.const 16)
                                  )
                                 )
                                 (local.set $2
                                  (i32.add
                                   (local.get $2)
                                   (i32.const 16)
                                  )
                                 )
                                 (local.set $6
                                  (i32.add
                                   (local.get $6)
                                   (i32.const 4)
                                  )
                                 )
                                 (br_if $label3
                                  (local.tee $20
                                   (i32.sub
                                    (local.get $20)
                                    (i32.const 2)
                                   )
                                  )
                                 )
                                )
                                (local.get $scratch)
                               )
                              )
                             )
                            )
                           )
                           (local.set $8
                            (i32.load
                             (local.tee $2
                              (i32.add
                               (local.get $13)
                               (i32.shl
                                (i32.xor
                                 (local.get $6)
                                 (i32.const -1)
                                )
                                (i32.const 2)
                               )
                              )
                             )
                            )
                           )
                           (i32.store
                            (local.get $2)
                            (i32.load
                             (local.tee $2
                              (i32.add
                               (local.get $16)
                               (i32.shl
                                (local.get $6)
                                (i32.const 2)
                               )
                              )
                             )
                            )
                           )
                           (i32.store
                            (local.get $2)
                            (local.get $8)
                           )
                           (local.set $20
                            (i32.load
                             (local.tee $8
                              (i32.add
                               (local.get $13)
                               (i32.shl
                                (i32.xor
                                 (local.get $6)
                                 (i32.const 1073741822)
                                )
                                (i32.const 2)
                               )
                              )
                             )
                            )
                           )
                           (i32.store
                            (local.get $8)
                            (i32.load offset=4
                             (local.get $2)
                            )
                           )
                           (i32.store offset=4
                            (local.get $2)
                            (local.get $20)
                           )
                           (local.set $6
                            (i32.add
                             (local.get $6)
                             (i32.const 2)
                            )
                           )
                          )
                          (local.get $scratch_42)
                         )
                        )
                       )
                      )
                     )
                     (local.set $8
                      (i32.load
                       (local.tee $2
                        (i32.add
                         (local.get $16)
                         (i32.shl
                          (local.get $6)
                          (i32.const 2)
                         )
                        )
                       )
                      )
                     )
                     (i32.store
                      (local.get $2)
                      (i32.load
                       (local.tee $2
                        (i32.add
                         (local.get $13)
                         (i32.shl
                          (i32.xor
                           (local.get $6)
                           (i32.const -1)
                          )
                          (i32.const 2)
                         )
                        )
                       )
                      )
                     )
                     (i32.store
                      (local.get $2)
                      (local.get $8)
                     )
                    )
                    (block $block15
                     (br_if $block15
                      (i32.eqz
                       (local.tee $2
                        (i32.shr_u
                         (local.get $9)
                         (i32.const 1)
                        )
                       )
                      )
                     )
                     (local.set $6
                      (i32.const 0)
                     )
                     (if
                      (i32.ne
                       (local.get $2)
                       (i32.const 1)
                      )
                      (then
                       (br_if $block15
                        (i32.eqz
                         (block (result i32)
                          (local.set $scratch_44
                           (i32.and
                            (local.get $2)
                            (i32.const 1)
                           )
                          )
                          (block $block16
                           (if
                            (local.tee $2
                             (i32.shr_u
                              (i32.sub
                               (local.get $2)
                               (i32.const 2)
                              )
                              (i32.const 1)
                             )
                            )
                            (then
                             (br_if $block16
                              (i32.eqz
                               (block (result i32)
                                (local.set $scratch_43
                                 (i32.and
                                  (local.tee $2
                                   (i32.add
                                    (local.get $2)
                                    (i32.const 1)
                                   )
                                  )
                                  (i32.const 1)
                                 )
                                )
                                (local.set $9
                                 (i32.sub
                                  (local.get $10)
                                  (i32.const 4)
                                 )
                                )
                                (local.set $8
                                 (i32.and
                                  (local.get $2)
                                  (i32.const 2147483646)
                                 )
                                )
                                (local.set $2
                                 (local.get $15)
                                )
                                (loop $label4
                                 (local.set $17
                                  (i32.load
                                   (local.get $9)
                                  )
                                 )
                                 (i32.store
                                  (local.get $9)
                                  (i32.load
                                   (local.get $2)
                                  )
                                 )
                                 (local.set $19
                                  (i32.load
                                   (local.tee $18
                                    (i32.add
                                     (local.get $10)
                                     (i32.shl
                                      (i32.xor
                                       (local.get $6)
                                       (i32.const 1073741822)
                                      )
                                      (i32.const 2)
                                     )
                                    )
                                   )
                                  )
                                 )
                                 (i32.store
                                  (local.get $18)
                                  (i32.load
                                   (local.tee $18
                                    (i32.add
                                     (local.get $2)
                                     (i32.const 4)
                                    )
                                   )
                                  )
                                 )
                                 (local.set $28
                                  (i32.load
                                   (local.tee $14
                                    (i32.add
                                     (local.get $10)
                                     (i32.shl
                                      (i32.xor
                                       (local.get $6)
                                       (i32.const 1073741821)
                                      )
                                      (i32.const 2)
                                     )
                                    )
                                   )
                                  )
                                 )
                                 (i32.store
                                  (local.get $14)
                                  (i32.load
                                   (local.tee $14
                                    (i32.add
                                     (local.get $2)
                                     (i32.const 8)
                                    )
                                   )
                                  )
                                 )
                                 (i32.store
                                  (local.get $2)
                                  (local.get $17)
                                 )
                                 (i32.store
                                  (local.get $18)
                                  (local.get $19)
                                 )
                                 (i32.store
                                  (local.get $14)
                                  (local.get $28)
                                 )
                                 (local.set $18
                                  (i32.load
                                   (local.tee $17
                                    (i32.add
                                     (local.get $10)
                                     (i32.shl
                                      (i32.xor
                                       (local.get $6)
                                       (i32.const 1073741820)
                                      )
                                      (i32.const 2)
                                     )
                                    )
                                   )
                                  )
                                 )
                                 (i32.store
                                  (local.get $17)
                                  (i32.load
                                   (local.tee $17
                                    (i32.add
                                     (local.get $2)
                                     (i32.const 12)
                                    )
                                   )
                                  )
                                 )
                                 (i32.store
                                  (local.get $17)
                                  (local.get $18)
                                 )
                                 (local.set $9
                                  (i32.sub
                                   (local.get $9)
                                   (i32.const 16)
                                  )
                                 )
                                 (local.set $2
                                  (i32.add
                                   (local.get $2)
                                   (i32.const 16)
                                  )
                                 )
                                 (local.set $6
                                  (i32.add
                                   (local.get $6)
                                   (i32.const 4)
                                  )
                                 )
                                 (br_if $label4
                                  (local.tee $8
                                   (i32.sub
                                    (local.get $8)
                                    (i32.const 2)
                                   )
                                  )
                                 )
                                )
                                (local.get $scratch_43)
                               )
                              )
                             )
                            )
                           )
                           (local.set $9
                            (i32.load
                             (local.tee $2
                              (i32.add
                               (local.get $10)
                               (i32.shl
                                (i32.xor
                                 (local.get $6)
                                 (i32.const -1)
                                )
                                (i32.const 2)
                               )
                              )
                             )
                            )
                           )
                           (i32.store
                            (local.get $2)
                            (i32.load
                             (local.tee $2
                              (i32.add
                               (local.get $15)
                               (i32.shl
                                (local.get $6)
                                (i32.const 2)
                               )
                              )
                             )
                            )
                           )
                           (i32.store
                            (local.get $2)
                            (local.get $9)
                           )
                           (local.set $8
                            (i32.load
                             (local.tee $9
                              (i32.add
                               (local.get $10)
                               (i32.shl
                                (i32.xor
                                 (local.get $6)
                                 (i32.const 1073741822)
                                )
                                (i32.const 2)
                               )
                              )
                             )
                            )
                           )
                           (i32.store
                            (local.get $9)
                            (i32.load offset=4
                             (local.get $2)
                            )
                           )
                           (i32.store offset=4
                            (local.get $2)
                            (local.get $8)
                           )
                           (local.set $6
                            (i32.add
                             (local.get $6)
                             (i32.const 2)
                            )
                           )
                          )
                          (local.get $scratch_44)
                         )
                        )
                       )
                      )
                     )
                     (local.set $9
                      (i32.load
                       (local.tee $2
                        (i32.add
                         (local.get $15)
                         (i32.shl
                          (local.get $6)
                          (i32.const 2)
                         )
                        )
                       )
                      )
                     )
                     (i32.store
                      (local.get $2)
                      (i32.load
                       (local.tee $2
                        (i32.add
                         (local.get $10)
                         (i32.shl
                          (i32.xor
                           (local.get $6)
                           (i32.const -1)
                          )
                          (i32.const 2)
                         )
                        )
                       )
                      )
                     )
                     (i32.store
                      (local.get $2)
                      (local.get $9)
                     )
                    )
                    (if
                     (local.get $27)
                     (then
                      (if
                       (i32.eq
                        (local.tee $2
                         (i32.load offset=52
                          (local.get $5)
                         )
                        )
                        (i32.load offset=44
                         (local.get $5)
                        )
                       )
                       (then
                        (call $_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h59a3d2ed514a3c56E
                         (i32.add
                          (local.get $5)
                          (i32.const 44)
                         )
                        )
                       )
                      )
                      (i64.store align=4
                       (local.tee $6
                        (i32.add
                         (i32.load offset=48
                          (local.get $5)
                         )
                         (i32.mul
                          (local.get $2)
                          (i32.const 12)
                         )
                        )
                       )
                       (i64.load offset=56 align=4
                        (local.get $5)
                       )
                      )
                      (i32.store offset=8
                       (local.get $6)
                       (i32.load offset=64
                        (local.get $5)
                       )
                      )
                      (i32.store offset=52
                       (local.get $5)
                       (i32.add
                        (local.get $2)
                        (i32.const 1)
                       )
                      )
                     )
                    )
                    (br_if $block17
                     (local.get $31)
                    )
                    (if
                     (i32.eq
                      (local.tee $2
                       (i32.load offset=52
                        (local.get $5)
                       )
                      )
                      (i32.load offset=44
                       (local.get $5)
                      )
                     )
                     (then
                      (call $_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h59a3d2ed514a3c56E
                       (i32.add
                        (local.get $5)
                        (i32.const 44)
                       )
                      )
                     )
                    )
                    (i64.store align=4
                     (local.tee $6
                      (i32.add
                       (i32.load offset=48
                        (local.get $5)
                       )
                       (i32.mul
                        (local.get $2)
                        (i32.const 12)
                       )
                      )
                     )
                     (i64.load offset=68 align=4
                      (local.get $5)
                     )
                    )
                    (i32.store offset=8
                     (local.get $6)
                     (i32.load offset=76
                      (local.get $5)
                     )
                    )
                    (i32.store offset=52
                     (local.get $5)
                     (i32.add
                      (local.get $2)
                      (i32.const 1)
                     )
                    )
                    (br $block18)
                   )
                   (local.set $8
                    (i32.const -2147483647)
                   )
                   (br $block9)
                  )
                  (call $_RNvNtCsdHhIpgkcIfN_4core6option13unwrap_failed
                   (i32.const 1052220)
                  )
                  (unreachable)
                 )
                 (br_if $block18
                  (i32.eqz
                   (i32.load offset=68
                    (local.get $5)
                   )
                  )
                 )
                 (call $dlfree
                  (local.get $15)
                 )
                )
                (block $block19
                 (br_if $block19
                  (local.get $27)
                 )
                 (br_if $block19
                  (i32.eqz
                   (i32.load offset=56
                    (local.get $5)
                   )
                  )
                 )
                 (call $dlfree
                  (local.get $16)
                 )
                )
                (br_if $label5
                 (i32.ne
                  (local.get $33)
                  (local.tee $25
                   (i32.add
                    (local.get $25)
                    (i32.const 12)
                   )
                  )
                 )
                )
               )
               (br $block20)
              )
              (call $_RNvNtCsdHhIpgkcIfN_4core6option13unwrap_failed
               (i32.const 1052108)
              )
              (unreachable)
             )
             (if
              (i32.load offset=68
               (local.get $5)
              )
              (then
               (call $dlfree
                (i32.load offset=72
                 (local.get $5)
                )
               )
              )
             )
             (if
              (i32.load offset=56
               (local.get $5)
              )
              (then
               (call $dlfree
                (i32.load offset=60
                 (local.get $5)
                )
               )
              )
             )
             (local.set $6
              (i32.load offset=48
               (local.get $5)
              )
             )
             (if
              (local.tee $2
               (i32.load offset=52
                (local.get $5)
               )
              )
              (then
               (local.set $7
                (local.get $6)
               )
               (loop $label6
                (if
                 (i32.load
                  (local.get $7)
                 )
                 (then
                  (call $dlfree
                   (i32.load
                    (i32.add
                     (local.get $7)
                     (i32.const 4)
                    )
                   )
                  )
                 )
                )
                (local.set $7
                 (i32.add
                  (local.get $7)
                  (i32.const 12)
                 )
                )
                (br_if $label6
                 (local.tee $2
                  (i32.sub
                   (local.get $2)
                   (i32.const 1)
                  )
                 )
                )
               )
              )
             )
             (br_if $block21
              (i32.eqz
               (i32.load offset=44
                (local.get $5)
               )
              )
             )
             (call $dlfree
              (local.get $6)
             )
             (br $block21)
            )
            (i32.load offset=44
             (local.get $5)
            )
           )
          )
          (local.set $21
           (i32.wrap_i64
            (i64.shr_u
             (local.tee $38
              (i64.load offset=48 align=4
               (local.get $5)
              )
             )
             (i64.const 32)
            )
           )
          )
          (local.set $22
           (i32.wrap_i64
            (local.get $38)
           )
          )
         )
         (block $block22
          (block $block29
           (block $block31
            (block $block30
             (block $block24
              (block $block23
               (br_table $block22 $block23 $block24
                (i32.sub
                 (select
                  (i32.const 2)
                  (i32.xor
                   (local.get $8)
                   (i32.const -2147483648)
                  )
                  (i32.ge_s
                   (local.get $8)
                   (i32.const 0)
                  )
                 )
                 (i32.const 1)
                )
               )
              )
              (i32.store offset=68
               (local.get $5)
               (block $block28 (result i32)
                (block $block27
                 (block $block25
                  (block $block26
                   (if
                    (local.tee $2
                     (i32.load offset=12
                      (local.get $12)
                     )
                    )
                    (then
                     (i32.store
                      (local.get $2)
                      (local.tee $2
                       (i32.add
                        (i32.load
                         (local.get $2)
                        )
                        (i32.const 1)
                       )
                      )
                     )
                     (br_if $block25
                      (i32.eqz
                       (local.get $2)
                      )
                     )
                     (local.set $7
                      (i32.load offset=12
                       (local.get $12)
                      )
                     )
                     (br_if $block26
                      (local.get $11)
                     )
                     (br $block27)
                    )
                   )
                   (drop
                    (br_if $block28
                     (local.tee $7
                      (i32.const 0)
                     )
                     (i32.eqz
                      (local.get $11)
                     )
                    )
                   )
                  )
                  (local.set $2
                   (local.get $11)
                  )
                  (local.set $6
                   (local.get $7)
                  )
                  (loop $label7
                   (local.set $9
                    (if (result i32)
                     (local.tee $7
                      (i32.load offset=8
                       (local.get $2)
                      )
                     )
                     (then
                      (i32.store
                       (local.get $7)
                       (local.tee $7
                        (i32.add
                         (i32.load
                          (local.get $7)
                         )
                         (i32.const 1)
                        )
                       )
                      )
                      (br_if $block25
                       (i32.eqz
                        (local.get $7)
                       )
                      )
                      (i32.load offset=8
                       (local.get $2)
                      )
                     )
                     (else
                      (i32.const 0)
                     )
                    )
                   )
                   (if
                    (local.tee $7
                     (call $dlmalloc
                      (i32.const 16)
                     )
                    )
                    (then
                     (i32.store offset=12
                      (local.get $7)
                      (local.get $6)
                     )
                     (i32.store offset=8
                      (local.get $7)
                      (local.get $9)
                     )
                     (i64.store align=4
                      (local.get $7)
                      (i64.const 4294967297)
                     )
                     (local.set $6
                      (local.get $7)
                     )
                     (br_if $block27
                      (i32.eqz
                       (local.tee $2
                        (i32.load offset=12
                         (local.get $2)
                        )
                       )
                      )
                     )
                     (br $label7)
                    )
                   )
                  )
                  (call $_RNvNtCsi9YzqDQQz2q_5alloc5alloc18handle_alloc_error
                   (i32.const 4)
                   (i32.const 16)
                  )
                  (unreachable)
                 )
                 (unreachable)
                )
                (i32.store offset=76
                 (local.get $5)
                 (i32.const 0)
                )
                (i32.store offset=72
                 (local.get $5)
                 (local.get $7)
                )
                (i32.const 1)
               )
              )
              (br_if $block29
               (call $_ZN6matrix5zebra17hfa0b4bd4996b012aE
                (i32.add
                 (local.get $5)
                 (i32.const 68)
                )
                (local.get $1)
                (local.get $32)
                (local.get $22)
                (local.get $21)
               )
              )
              (if
               (local.get $21)
               (then
                (local.set $7
                 (local.get $22)
                )
                (loop $label8
                 (if
                  (i32.load
                   (local.get $7)
                  )
                  (then
                   (call $dlfree
                    (i32.load
                     (i32.add
                      (local.get $7)
                      (i32.const 4)
                     )
                    )
                   )
                  )
                 )
                 (local.set $7
                  (i32.add
                   (local.get $7)
                   (i32.const 12)
                  )
                 )
                 (br_if $label8
                  (local.tee $21
                   (i32.sub
                    (local.get $21)
                    (i32.const 1)
                   )
                  )
                 )
                )
               )
              )
              (br_if $block24
               (i32.eqz
                (local.get $8)
               )
              )
              (call $dlfree
               (local.get $22)
              )
              (br_if $block30
               (i32.eqz
                (local.get $23)
               )
              )
              (br $block31)
             )
             (br_if $block31
              (local.get $23)
             )
            )
            (call $dlfree
             (local.get $26)
            )
           )
           (i32.store
            (local.get $12)
            (local.tee $0
             (i32.sub
              (i32.load
               (local.get $12)
              )
              (i32.const 1)
             )
            )
           )
           (if
            (i32.eqz
             (local.get $0)
            )
            (then
             (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
              (i32.add
               (local.get $5)
               (i32.const 8)
              )
             )
            )
           )
           (block $block32
            (br_if $block32
             (i32.eqz
              (local.get $11)
             )
            )
            (i32.store
             (local.get $11)
             (local.tee $0
              (i32.sub
               (i32.load
                (local.get $11)
               )
               (i32.const 1)
              )
             )
            )
            (br_if $block32
             (local.get $0)
            )
            (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
             (local.get $30)
            )
           )
           (local.set $7
            (i32.const 0)
           )
           (br $block)
          )
          (if
           (local.get $21)
           (then
            (local.set $7
             (local.get $22)
            )
            (local.set $2
             (local.get $21)
            )
            (loop $label9
             (if
              (i32.load
               (local.get $7)
              )
              (then
               (call $dlfree
                (i32.load
                 (i32.add
                  (local.get $7)
                  (i32.const 4)
                 )
                )
               )
              )
             )
             (local.set $7
              (i32.add
               (local.get $7)
               (i32.const 12)
              )
             )
             (br_if $label9
              (local.tee $2
               (i32.sub
                (local.get $2)
                (i32.const 1)
               )
              )
             )
            )
           )
          )
          (br_if $block22
           (i32.eqz
            (local.get $8)
           )
          )
          (call $dlfree
           (local.get $22)
          )
         )
         (if
          (i32.eqz
           (local.get $23)
          )
          (then
           (call $dlfree
            (local.get $26)
           )
          )
         )
         (local.set $7
          (i32.const 1)
         )
         (br_if $label10
          (i32.ne
           (local.get $36)
           (i32.const 2)
          )
         )
        )
        (br $block33)
       )
      )
      (call $_RNvNtCsdHhIpgkcIfN_4core6option13unwrap_failed
       (i32.const 1052156)
      )
      (unreachable)
     )
     (call $_ZN6matrix11Permutation7brother17h371b75b5f64de937E
      (local.get $0)
      (local.get $12)
      (local.get $11)
     )
     (i32.store
      (local.get $12)
      (local.tee $2
       (i32.sub
        (i32.load
         (local.get $12)
        )
        (i32.const 1)
       )
      )
     )
     (if
      (i32.eqz
       (local.get $2)
      )
      (then
       (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
        (i32.add
         (local.get $5)
         (i32.const 8)
        )
       )
      )
     )
     (block $block34
      (br_if $block34
       (i32.eqz
        (local.get $11)
       )
      )
      (i32.store
       (local.get $11)
       (local.tee $2
        (i32.sub
         (i32.load
          (local.get $11)
         )
         (i32.const 1)
        )
       )
      )
      (br_if $block34
       (local.get $2)
      )
      (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
       (local.get $30)
      )
     )
     (br_if $label11
      (i32.load
       (local.get $0)
      )
     )
    )
   )
   (global.set $__stack_pointer
    (i32.add
     (local.get $5)
     (i32.const 80)
    )
   )
   (return
    (local.get $7)
   )
  )
  (call $_RNvNtCsdHhIpgkcIfN_4core6option13unwrap_failed
   (i32.const 1052436)
  )
  (unreachable)
 )
