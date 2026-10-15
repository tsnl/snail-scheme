(func $_ZN4sum14main17hb29c827d4a252442E (param $0 i32)
  (local $1 i32)
  (local $2 i32)
  (local $3 i32)
  (local $4 i32)
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
  (local $29 i64)
  (local $30 i64)
  (local $31 i64)
  (local $32 i64)
  (local $33 f64)
  (local $34 f64)
  (local $35 f64)
  (local $scratch i32)
  (local $scratch_37 i64)
  (local $scratch_38 i32)
  (global.set $__stack_pointer
   (local.tee $1
    (i32.sub
     (global.get $__stack_pointer)
     (i32.const 464)
    )
   )
  )
  (i64.store offset=32 align=4
   (local.get $1)
   (i64.const 4294967296)
  )
  (i32.store offset=40
   (local.get $1)
   (i32.const 0)
  )
  (if
   (i32.ne
    (local.tee $2
     (i32.load8_u
      (i32.const 1077436)
     )
    )
    (i32.const 3)
   )
   (then
    (block $block1
     (block $block
      (block $block2
       (br_table $block $block1 $block2
        (i32.sub
         (local.get $2)
         (i32.const 2)
        )
       )
      )
      (i32.store8
       (i32.const 1077436)
       (i32.const 2)
      )
      (if
       (local.tee $2
        (call $dlmalloc
         (i32.const 8192)
        )
       )
       (then
        (i32.store8
         (i32.const 1077436)
         (i32.const 3)
        )
        (i64.store align=4
         (i32.const 1077428)
         (i64.const 0)
        )
        (i64.store align=4
         (i32.const 1077420)
         (i64.const 8192)
        )
        (i32.store
         (i32.const 1077416)
         (local.get $2)
        )
        (i32.store8
         (i32.const 1077412)
         (i32.const 0)
        )
        (br $block1)
       )
      )
      (call $_RNvNtCsi9YzqDQQz2q_5alloc7raw_vec12handle_error
       (i32.const 1)
       (i32.const 8192)
      )
      (unreachable)
     )
     (call $_RNvNtCsdHhIpgkcIfN_4core9panicking9panic_fmt
      (i32.const 1070930)
      (i32.const 113)
      (i32.const 1070872)
     )
     (unreachable)
    )
   )
  )
  (local.set $2
   (i32.load8_u
    (i32.const 1077412)
   )
  )
  (i32.store8
   (i32.const 1077412)
   (i32.const 1)
  )
  (i32.store8 offset=48
   (local.get $1)
   (local.get $2)
  )
  (block $block32
   (block $block31
    (block $block77
     (block $block20
      (block $block27
       (block $block19
        (block $block24
         (block $block22
          (if
           (i32.ne
            (local.get $2)
            (i32.const 1)
           )
           (then
            (local.set $15
             (i32.add
              (local.get $1)
              (i32.const 448)
             )
            )
            (global.set $__stack_pointer
             (local.tee $5
              (i32.sub
               (global.get $__stack_pointer)
               (i32.const 32)
              )
             )
            )
            (local.set $8
             (i32.load
              (i32.const 1077416)
             )
            )
            (block $block4
             (if
              (i32.gt_u
               (local.tee $14
                (i32.sub
                 (local.tee $12
                  (i32.load
                   (i32.const 1077428)
                  )
                 )
                 (local.tee $4
                  (i32.load
                   (i32.const 1077424)
                  )
                 )
                )
               )
               (i32.sub
                (local.tee $7
                 (i32.load
                  (local.tee $9
                   (i32.add
                    (local.get $1)
                    (i32.const 32)
                   )
                  )
                 )
                )
                (local.tee $2
                 (i32.load offset=8
                  (local.get $9)
                 )
                )
               )
              )
              (then
               (block $block3
                (if
                 (i32.le_u
                  (local.get $14)
                  (local.tee $3
                   (i32.add
                    (local.get $2)
                    (local.get $14)
                   )
                  )
                 )
                 (then
                  (call $_RNvMs4_NtCsi9YzqDQQz2q_5alloc7raw_vecNtB5_11RawVecInner11finish_growCset5xJoy1xWQ_3std
                   (local.get $5)
                   (local.get $7)
                   (i32.load offset=4
                    (local.get $9)
                   )
                   (local.tee $7
                    (select
                     (i32.const 8)
                     (local.tee $7
                      (select
                       (local.get $3)
                       (local.tee $7
                        (i32.shl
                         (local.get $7)
                         (i32.const 1)
                        )
                       )
                       (i32.gt_u
                        (local.get $3)
                        (local.get $7)
                       )
                      )
                     )
                     (i32.le_u
                      (local.get $7)
                      (i32.const 8)
                     )
                    )
                   )
                  )
                  (br_if $block3
                   (i32.ne
                    (i32.load
                     (local.get $5)
                    )
                    (i32.const 1)
                   )
                  )
                 )
                )
                (i64.store align=4
                 (local.get $15)
                 (i64.const 9729)
                )
                (br $block4)
               )
               (local.set $3
                (i32.load offset=4
                 (local.get $5)
                )
               )
               (i32.store
                (local.get $9)
                (local.get $7)
               )
               (i32.store offset=4
                (local.get $9)
                (local.get $3)
               )
              )
             )
             (block $block5
              (br_if $block5
               (i32.eq
                (local.get $4)
                (local.get $12)
               )
              )
              (br_if $block5
               (i32.eqz
                (local.get $14)
               )
              )
              (memory.copy
               (i32.add
                (i32.load offset=4
                 (local.get $9)
                )
                (local.get $2)
               )
               (i32.add
                (local.get $4)
                (local.get $8)
               )
               (local.get $14)
              )
             )
             (i64.store align=4
              (i32.const 1077424)
              (i64.const 0)
             )
             (i32.store offset=8
              (local.get $9)
              (local.tee $3
               (i32.add
                (local.get $2)
                (local.get $14)
               )
              )
             )
             (block $block10
              (block $block15
               (block $block7
                (block $block6
                 (if
                  (i32.ge_u
                   (local.tee $10
                    (i32.sub
                     (local.get $7)
                     (local.get $3)
                    )
                   )
                   (i32.const 32)
                  )
                  (then
                   (local.set $2
                    (local.get $7)
                   )
                   (local.set $4
                    (local.get $3)
                   )
                   (br $block6)
                  )
                 )
                 (i64.store offset=24
                  (local.get $5)
                  (i64.const 0)
                 )
                 (i64.store offset=16
                  (local.get $5)
                  (i64.const 0)
                 )
                 (i64.store offset=8
                  (local.get $5)
                  (i64.const 0)
                 )
                 (i64.store
                  (local.get $5)
                  (i64.const 0)
                 )
                 (loop $label
                  (if
                   (i32.eq
                    (local.tee $4
                     (call $read
                      (i32.const 0)
                      (local.get $5)
                      (i32.const 32)
                     )
                    )
                    (i32.const -1)
                   )
                   (then
                    (br_if $label
                     (i32.eq
                      (local.tee $8
                       (i32.load
                        (i32.const 1077468)
                       )
                      )
                      (i32.const 27)
                     )
                    )
                    (br $block7)
                   )
                  )
                 )
                 (if
                  (i32.lt_u
                   (local.get $4)
                   (i32.const 33)
                  )
                  (then
                   (block $block9
                    (block $block8
                     (if
                      (i32.gt_u
                       (local.get $4)
                       (local.get $10)
                      )
                      (then
                       (call $_RINvNvMs2_NtCsi9YzqDQQz2q_5alloc7raw_vecINtB8_11RawVecInnerpE7reserve21do_reserve_and_handleNtNtBa_5alloc6GlobalECset5xJoy1xWQ_3std
                        (local.get $9)
                        (local.get $3)
                        (local.get $4)
                       )
                       (local.set $2
                        (i32.load
                         (local.get $9)
                        )
                       )
                       (local.set $8
                        (i32.load offset=8
                         (local.get $9)
                        )
                       )
                       (br $block8)
                      )
                     )
                     (local.set $2
                      (local.get $7)
                     )
                     (local.set $8
                      (local.get $3)
                     )
                     (br_if $block9
                      (i32.eqz
                       (local.get $4)
                      )
                     )
                    )
                    (if
                     (local.get $4)
                     (then
                      (memory.copy
                       (i32.add
                        (i32.load offset=4
                         (local.get $9)
                        )
                        (local.get $8)
                       )
                       (local.get $5)
                       (local.get $4)
                      )
                     )
                    )
                    (i32.store offset=8
                     (local.get $9)
                     (local.tee $4
                      (i32.add
                       (local.get $4)
                       (local.get $8)
                      )
                     )
                    )
                    (br $block6)
                   )
                   (local.set $10
                    (i32.const 0)
                   )
                   (br $block10)
                  )
                 )
                 (call $_RNvNtNtCsdHhIpgkcIfN_4core5slice5index16slice_index_fail
                  (i32.const 0)
                  (local.get $4)
                  (i32.const 32)
                  (i32.const 1071344)
                 )
                 (unreachable)
                )
                (local.set $12
                 (i32.const 8192)
                )
                (block $block14
                 (loop $label3
                  (block $block11
                   (if
                    (i32.eqz
                     (i32.and
                      (i32.eq
                       (local.get $2)
                       (local.get $4)
                      )
                      (i32.eq
                       (local.get $2)
                       (local.get $7)
                      )
                     )
                    )
                    (then
                     (local.set $8
                      (i32.load offset=4
                       (local.get $9)
                      )
                     )
                     (br $block11)
                    )
                   )
                   (i64.store offset=24
                    (local.get $5)
                    (i64.const 0)
                   )
                   (i64.store offset=16
                    (local.get $5)
                    (i64.const 0)
                   )
                   (i64.store offset=8
                    (local.get $5)
                    (i64.const 0)
                   )
                   (i64.store
                    (local.get $5)
                    (i64.const 0)
                   )
                   (loop $label1
                    (if
                     (i32.eq
                      (local.tee $2
                       (call $read
                        (i32.const 0)
                        (local.get $5)
                        (i32.const 32)
                       )
                      )
                      (i32.const -1)
                     )
                     (then
                      (br_if $label1
                       (i32.eq
                        (local.tee $8
                         (i32.load
                          (i32.const 1077468)
                         )
                        )
                        (i32.const 27)
                       )
                      )
                      (br $block7)
                     )
                    )
                   )
                   (if
                    (i32.lt_u
                     (local.get $2)
                     (i32.const 33)
                    )
                    (then
                     (if
                      (local.get $2)
                      (then
                       (call $_RINvNvMs2_NtCsi9YzqDQQz2q_5alloc7raw_vecINtB8_11RawVecInnerpE7reserve21do_reserve_and_handleNtNtBa_5alloc6GlobalECset5xJoy1xWQ_3std
                        (local.get $9)
                        (local.get $7)
                        (local.get $2)
                       )
                       (local.set $4
                        (i32.load offset=8
                         (local.get $9)
                        )
                       )
                       (local.set $8
                        (i32.load offset=4
                         (local.get $9)
                        )
                       )
                       (if
                        (local.get $2)
                        (then
                         (memory.copy
                          (i32.add
                           (local.get $4)
                           (local.get $8)
                          )
                          (local.get $5)
                          (local.get $2)
                         )
                        )
                       )
                       (i32.store offset=8
                        (local.get $9)
                        (local.tee $4
                         (i32.add
                          (local.get $2)
                          (local.get $4)
                         )
                        )
                       )
                       (local.set $2
                        (i32.load
                         (local.get $9)
                        )
                       )
                       (br $block11)
                      )
                     )
                     (i32.store offset=8
                      (local.get $9)
                      (local.get $7)
                     )
                     (br $block10)
                    )
                   )
                   (call $_RNvNtNtCsdHhIpgkcIfN_4core5slice5index16slice_index_fail
                    (i32.const 0)
                    (local.get $2)
                    (i32.const 32)
                    (i32.const 1071344)
                   )
                   (unreachable)
                  )
                  (block $block12
                   (if
                    (i32.eq
                     (local.get $2)
                     (local.get $4)
                    )
                    (then
                     (call $_RNvMs4_NtCsi9YzqDQQz2q_5alloc7raw_vecNtB5_11RawVecInner11finish_growCset5xJoy1xWQ_3std
                      (local.get $5)
                      (local.get $2)
                      (local.get $8)
                      (local.tee $2
                       (select
                        (local.tee $8
                         (i32.add
                          (local.get $2)
                          (i32.const 32)
                         )
                        )
                        (local.tee $2
                         (i32.shl
                          (local.get $2)
                          (i32.const 1)
                         )
                        )
                        (i32.lt_u
                         (local.get $2)
                         (local.get $8)
                        )
                       )
                      )
                     )
                     (br_if $block12
                      (i32.load
                       (local.get $5)
                      )
                     )
                     (local.set $8
                      (i32.load offset=4
                       (local.get $5)
                      )
                     )
                     (i32.store
                      (local.get $9)
                      (local.get $2)
                     )
                     (i32.store offset=4
                      (local.get $9)
                      (local.get $8)
                     )
                    )
                   )
                   (local.set $13
                    (select
                     (i32.const 2147483647)
                     (local.tee $11
                      (select
                       (local.get $12)
                       (local.tee $11
                        (i32.sub
                         (local.get $2)
                         (local.get $4)
                        )
                       )
                       (i32.gt_u
                        (local.get $11)
                        (local.get $12)
                       )
                      )
                     )
                     (i32.ge_u
                      (local.get $11)
                      (i32.const 2147483647)
                     )
                    )
                   )
                   (local.set $18
                    (i32.add
                     (local.get $4)
                     (local.get $8)
                    )
                   )
                   (block $block13
                    (loop $label2
                     (br_if $block13
                      (i32.ne
                       (local.tee $8
                        (call $read
                         (i32.const 0)
                         (local.get $18)
                         (local.get $13)
                        )
                       )
                       (i32.const -1)
                      )
                     )
                     (br_if $label2
                      (i32.eq
                       (local.tee $8
                        (i32.load
                         (i32.const 1077468)
                        )
                       )
                       (i32.const 27)
                      )
                     )
                    )
                    (i32.store offset=8
                     (local.get $9)
                     (local.get $4)
                    )
                    (br $block7)
                   )
                   (i32.store offset=8
                    (local.get $9)
                    (local.tee $4
                     (i32.add
                      (local.get $4)
                      (local.get $8)
                     )
                    )
                   )
                   (br_if $block14
                    (i32.eqz
                     (local.get $8)
                    )
                   )
                   (local.set $16
                    (i32.sub
                     (local.tee $13
                      (select
                       (local.get $8)
                       (local.get $16)
                       (i32.gt_u
                        (local.get $8)
                        (local.get $16)
                       )
                      )
                     )
                     (local.get $8)
                    )
                   )
                   (local.set $12
                    (select
                     (select
                      (i32.const -1)
                      (local.get $12)
                      (i32.gt_s
                       (local.tee $17
                        (select
                         (i32.add
                          (local.get $17)
                          (i32.const 1)
                         )
                         (i32.const 0)
                         (i32.lt_u
                          (local.get $8)
                          (local.get $11)
                         )
                        )
                       )
                       (i32.const 1)
                      )
                     )
                     (local.get $12)
                     (i32.ne
                      (local.get $11)
                      (local.get $13)
                     )
                    )
                   )
                   (br_if $label3
                    (i32.ne
                     (local.get $8)
                     (local.get $11)
                    )
                   )
                   (br_if $label3
                    (i32.lt_u
                     (local.get $11)
                     (local.get $12)
                    )
                   )
                   (br_if $label3
                    (block (result i32)
                     (local.set $scratch
                      (i32.ge_s
                       (local.get $12)
                       (i32.const 0)
                      )
                     )
                     (local.set $12
                      (i32.shl
                       (local.get $12)
                       (i32.const 1)
                      )
                     )
                     (local.get $scratch)
                    )
                   )
                   (local.set $12
                    (i32.const -1)
                   )
                   (br $label3)
                  )
                 )
                 (local.set $8
                  (i32.const 0)
                 )
                 (local.set $29
                  (i64.const 9729)
                 )
                 (br $block15)
                )
                (local.set $10
                 (i32.sub
                  (local.get $4)
                  (local.get $3)
                 )
                )
                (br $block10)
               )
               (local.set $10
                (i32.const 0)
               )
               (br_if $block10
                (i32.eq
                 (local.get $8)
                 (i32.const 8)
                )
               )
              )
              (i64.store align=4
               (local.get $15)
               (i64.or
                (i64.shl
                 (i64.extend_i32_u
                  (local.get $8)
                 )
                 (i64.const 32)
                )
                (local.get $29)
               )
              )
              (br $block4)
             )
             (i32.store8
              (local.get $15)
              (i32.const 4)
             )
             (i32.store offset=4
              (local.get $15)
              (i32.add
               (local.get $10)
               (local.get $14)
              )
             )
            )
            (global.set $__stack_pointer
             (i32.add
              (local.get $5)
              (i32.const 32)
             )
            )
            (call $_RNvNtNtCsdHhIpgkcIfN_4core3str8converts9from_utf8
             (i32.add
              (local.get $1)
              (i32.const 48)
             )
             (local.tee $5
              (i32.load offset=36
               (local.get $1)
              )
             )
             (local.tee $3
              (i32.load offset=40
               (local.get $1)
              )
             )
            )
            (block $block17
             (block $block18
              (block $block16
               (if
                (i32.load offset=48
                 (local.get $1)
                )
                (then
                 (if
                  (i32.ne
                   (i32.load8_u offset=448
                    (local.get $1)
                   )
                   (i32.const 4)
                  )
                  (then
                   (i32.store8
                    (i32.const 1077412)
                    (i32.const 0)
                   )
                   (i32.store offset=40
                    (local.get $1)
                    (i32.const 0)
                   )
                   (br $block16)
                  )
                 )
                 (i32.store offset=40
                  (local.get $1)
                  (i32.const 0)
                 )
                 (i32.store8
                  (i32.const 1077412)
                  (i32.const 0)
                 )
                 (i64.store offset=448
                  (local.get $1)
                  (local.tee $29
                   (i64.load
                    (i32.const 1071056)
                   )
                  )
                 )
                 (br_if $block16
                  (i32.ne
                   (i32.and
                    (i32.wrap_i64
                     (local.get $29)
                    )
                    (i32.const 255)
                   )
                   (i32.const 4)
                  )
                 )
                 (local.set $4
                  (i32.const 4)
                 )
                 (local.set $3
                  (i32.const 0)
                 )
                 (br $block17)
                )
               )
               (i32.store offset=40
                (local.get $1)
                (local.get $3)
               )
               (i32.store8
                (i32.const 1077412)
                (i32.const 0)
               )
               (local.set $4
                (i32.const 4)
               )
               (br_if $block18
                (i32.eq
                 (i32.load8_u offset=448
                  (local.get $1)
                 )
                 (i32.const 4)
                )
               )
              )
              (local.set $12
               (i32.wrap_i64
                (i64.shr_u
                 (local.tee $29
                  (i64.load offset=448
                   (local.get $1)
                  )
                 )
                 (i64.const 32)
                )
               )
              )
              (local.set $7
               (i32.wrap_i64
                (local.get $29)
               )
              )
              (local.set $15
               (i32.const -2147483648)
              )
              (br_if $block19
               (i32.load offset=32
                (local.get $1)
               )
              )
              (br $block20)
             )
             (if
              (i32.eqz
               (local.get $3)
              )
              (then
               (local.set $3
                (i32.const 0)
               )
               (br $block17)
              )
             )
             (local.set $2
              (block $block21 (result i32)
               (if
                (i32.ge_s
                 (local.tee $2
                  (i32.load8_s
                   (local.get $5)
                  )
                 )
                 (i32.const 0)
                )
                (then
                 (local.set $7
                  (i32.and
                   (local.get $2)
                   (i32.const 255)
                  )
                 )
                 (br $block21
                  (i32.add
                   (local.get $5)
                   (i32.const 1)
                  )
                 )
                )
               )
               (local.set $4
                (i32.and
                 (i32.load8_u offset=1
                  (local.get $5)
                 )
                 (i32.const 63)
                )
               )
               (local.set $7
                (i32.and
                 (local.get $2)
                 (i32.const 31)
                )
               )
               (if
                (i32.le_u
                 (local.get $2)
                 (i32.const -33)
                )
                (then
                 (local.set $7
                  (i32.or
                   (i32.shl
                    (local.get $7)
                    (i32.const 6)
                   )
                   (local.get $4)
                  )
                 )
                 (br $block21
                  (i32.add
                   (local.get $5)
                   (i32.const 2)
                  )
                 )
                )
               )
               (local.set $8
                (i32.or
                 (i32.and
                  (i32.load8_u offset=2
                   (local.get $5)
                  )
                  (i32.const 63)
                 )
                 (i32.shl
                  (local.get $4)
                  (i32.const 6)
                 )
                )
               )
               (if
                (i32.lt_u
                 (local.get $2)
                 (i32.const -16)
                )
                (then
                 (local.set $7
                  (i32.or
                   (local.get $8)
                   (i32.shl
                    (local.get $7)
                    (i32.const 12)
                   )
                  )
                 )
                 (br $block21
                  (i32.add
                   (local.get $5)
                   (i32.const 3)
                  )
                 )
                )
               )
               (local.set $4
                (i32.const 4)
               )
               (if
                (i32.eq
                 (local.tee $7
                  (i32.or
                   (i32.and
                    (i32.shl
                     (local.get $7)
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
                     (local.get $8)
                     (i32.const 6)
                    )
                   )
                  )
                 )
                 (i32.const 1114112)
                )
                (then
                 (local.set $3
                  (i32.const 0)
                 )
                 (br $block17)
                )
               )
               (i32.add
                (local.get $5)
                (i32.const 4)
               )
              )
             )
             (br_if $block22
              (i32.gt_u
               (local.tee $4
                (i32.add
                 (i32.shr_u
                  (local.tee $4
                   (i32.sub
                    (local.tee $8
                     (i32.add
                      (local.get $3)
                      (local.get $5)
                     )
                    )
                    (local.get $2)
                   )
                  )
                  (i32.const 2)
                 )
                 (i32.ne
                  (i32.and
                   (local.get $4)
                   (i32.const 3)
                  )
                  (i32.const 0)
                 )
                )
               )
               (i32.const 1073741822)
              )
             )
             (br_if $block22
              (i32.ge_u
               (local.tee $9
                (i32.shl
                 (local.tee $3
                  (i32.add
                   (select
                    (i32.const 3)
                    (local.get $4)
                    (i32.le_u
                     (local.get $4)
                     (i32.const 3)
                    )
                   )
                   (i32.const 1)
                  )
                 )
                 (i32.const 2)
                )
               )
               (i32.const 2147483645)
              )
             )
             (block $block23
              (if
               (i32.eqz
                (local.get $9)
               )
               (then
                (local.set $4
                 (i32.const 4)
                )
                (local.set $3
                 (i32.const 0)
                )
                (br $block23)
               )
              )
              (br_if $block24
               (i32.eqz
                (local.tee $4
                 (call $dlmalloc
                  (local.get $9)
                 )
                )
               )
              )
             )
             (i32.store
              (local.get $4)
              (local.get $7)
             )
             (local.set $6
              (i32.const 1)
             )
             (i32.store offset=56
              (local.get $1)
              (i32.const 1)
             )
             (i32.store offset=52
              (local.get $1)
              (local.get $4)
             )
             (i32.store offset=48
              (local.get $1)
              (local.get $3)
             )
             (br_if $block17
              (i32.eq
               (local.get $2)
               (local.get $8)
              )
             )
             (local.set $5
              (i32.const 4)
             )
             (loop $label4
              (block $block26
               (local.set $2
                (block $block25 (result i32)
                 (if
                  (i32.ge_s
                   (local.tee $7
                    (i32.load8_s
                     (local.get $2)
                    )
                   )
                   (i32.const 0)
                  )
                  (then
                   (local.set $3
                    (i32.and
                     (local.get $7)
                     (i32.const 255)
                    )
                   )
                   (br $block25
                    (i32.add
                     (local.get $2)
                     (i32.const 1)
                    )
                   )
                  )
                 )
                 (local.set $9
                  (i32.and
                   (i32.load8_u offset=1
                    (local.get $2)
                   )
                   (i32.const 63)
                  )
                 )
                 (local.set $3
                  (i32.and
                   (local.get $7)
                   (i32.const 31)
                  )
                 )
                 (if
                  (i32.le_u
                   (local.get $7)
                   (i32.const -33)
                  )
                  (then
                   (local.set $3
                    (i32.or
                     (i32.shl
                      (local.get $3)
                      (i32.const 6)
                     )
                     (local.get $9)
                    )
                   )
                   (br $block25
                    (i32.add
                     (local.get $2)
                     (i32.const 2)
                    )
                   )
                  )
                 )
                 (local.set $9
                  (i32.or
                   (i32.and
                    (i32.load8_u offset=2
                     (local.get $2)
                    )
                    (i32.const 63)
                   )
                   (i32.shl
                    (local.get $9)
                    (i32.const 6)
                   )
                  )
                 )
                 (if
                  (i32.lt_u
                   (local.get $7)
                   (i32.const -16)
                  )
                  (then
                   (local.set $3
                    (i32.or
                     (local.get $9)
                     (i32.shl
                      (local.get $3)
                      (i32.const 12)
                     )
                    )
                   )
                   (br $block25
                    (i32.add
                     (local.get $2)
                     (i32.const 3)
                    )
                   )
                  )
                 )
                 (br_if $block26
                  (i32.eq
                   (local.tee $3
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
                       (local.get $9)
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
               (if
                (i32.eq
                 (i32.load offset=48
                  (local.get $1)
                 )
                 (local.get $6)
                )
                (then
                 (call $_ZN5alloc7raw_vec20RawVecInner$LT$A$GT$7reserve21do_reserve_and_handle17h9f5e8ff74fa33f13E
                  (i32.add
                   (local.get $1)
                   (i32.const 48)
                  )
                  (local.get $6)
                  (i32.add
                   (i32.add
                    (i32.shr_u
                     (local.tee $7
                      (i32.sub
                       (local.get $8)
                       (local.get $2)
                      )
                     )
                     (i32.const 2)
                    )
                    (i32.ne
                     (i32.and
                      (local.get $7)
                      (i32.const 3)
                     )
                     (i32.const 0)
                    )
                   )
                   (i32.const 1)
                  )
                  (i32.const 4)
                  (i32.const 4)
                 )
                 (local.set $4
                  (i32.load offset=52
                   (local.get $1)
                  )
                 )
                )
               )
               (i32.store
                (i32.add
                 (local.get $4)
                 (local.get $5)
                )
                (local.get $3)
               )
               (i32.store offset=56
                (local.get $1)
                (local.tee $6
                 (i32.add
                  (local.get $6)
                  (i32.const 1)
                 )
                )
               )
               (local.set $5
                (i32.add
                 (local.get $5)
                 (i32.const 4)
                )
               )
               (br_if $label4
                (i32.ne
                 (local.get $2)
                 (local.get $8)
                )
               )
              )
             )
             (local.set $4
              (i32.load offset=52
               (local.get $1)
              )
             )
             (local.set $3
              (i32.load offset=48
               (local.get $1)
              )
             )
            )
            (local.set $5
             (i32.const 0)
            )
            (i32.store offset=460
             (local.get $1)
             (i32.const 0)
            )
            (i32.store offset=456
             (local.get $1)
             (local.get $6)
            )
            (i32.store offset=452
             (local.get $1)
             (local.get $4)
            )
            (i32.store offset=448
             (local.get $1)
             (local.get $3)
            )
            (i32.store offset=440
             (local.get $1)
             (i32.const 0)
            )
            (i64.store offset=432 align=4
             (local.get $1)
             (i64.const 17179869184)
            )
            (local.set $3
             (i32.const 4)
            )
            (local.set $2
             (i32.const 1)
            )
            (loop $label5
             (if
              (call $_ZN19r7rs_wasm_reference6Reader10skip_space17hc8e85a88c7b465a6E
               (local.tee $7
                (i32.add
                 (local.get $1)
                 (i32.const 448)
                )
               )
              )
              (then
               (call $_ZN19r7rs_wasm_reference6Reader5datum17he48e33283fe96aafE
                (i32.add
                 (local.get $1)
                 (i32.const 48)
                )
                (local.get $7)
               )
               (if
                (i32.eq
                 (i32.load offset=432
                  (local.get $1)
                 )
                 (i32.sub
                  (local.get $2)
                  (i32.const 1)
                 )
                )
                (then
                 (call $_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h08be66b2cf009c70E
                  (i32.add
                   (local.get $1)
                   (i32.const 432)
                  )
                 )
                 (local.set $3
                  (i32.load offset=436
                   (local.get $1)
                  )
                 )
                )
               )
               (i64.store align=4
                (local.tee $7
                 (i32.add
                  (local.get $3)
                  (local.get $5)
                 )
                )
                (i64.load offset=48 align=4
                 (local.get $1)
                )
               )
               (i64.store offset=8 align=4
                (local.get $7)
                (i64.load offset=56 align=4
                 (local.get $1)
                )
               )
               (local.set $5
                (i32.add
                 (local.get $5)
                 (i32.const 16)
                )
               )
               (i32.store offset=440
                (local.get $1)
                (local.get $2)
               )
               (local.set $2
                (i32.add
                 (local.get $2)
                 (i32.const 1)
                )
               )
               (br $label5)
              )
              (else
               (local.set $12
                (i32.wrap_i64
                 (block (result i64)
                  (local.set $scratch_37
                   (i64.shr_u
                    (local.tee $29
                     (i64.load offset=436 align=4
                      (local.get $1)
                     )
                    )
                    (i64.const 32)
                   )
                  )
                  (local.set $15
                   (i32.load offset=432
                    (local.get $1)
                   )
                  )
                  (if
                   (i32.load offset=448
                    (local.get $1)
                   )
                   (then
                    (call $dlfree
                     (i32.load offset=452
                      (local.get $1)
                     )
                    )
                   )
                  )
                  (local.get $scratch_37)
                 )
                )
               )
               (local.set $7
                (i32.wrap_i64
                 (local.get $29)
                )
               )
               (br_if $block27
                (i32.eqz
                 (i32.load offset=32
                  (local.get $1)
                 )
                )
               )
               (local.set $5
                (i32.load offset=36
                 (local.get $1)
                )
               )
               (br $block19)
              )
             )
             (unreachable)
            )
            (unreachable)
           )
          )
          (call $_RINvNtCsdHhIpgkcIfN_4core9panicking13assert_failedbbECset5xJoy1xWQ_3std
           (i32.add
            (local.get $1)
            (i32.const 48)
           )
          )
          (unreachable)
         )
         (call $_RNvNtCsi9YzqDQQz2q_5alloc7raw_vec17capacity_overflow)
         (unreachable)
        )
        (call $_RNvNtCsi9YzqDQQz2q_5alloc7raw_vec12handle_error
         (i32.const 4)
         (local.get $9)
        )
        (unreachable)
       )
       (call $dlfree
        (local.get $5)
       )
      )
      (br_if $block20
       (i32.eq
        (local.get $15)
        (i32.const -2147483648)
       )
      )
      (if
       (local.get $12)
       (then
        (local.set $18
         (call $_ZN19r7rs_wasm_reference5Datum6number17hbd6eb5e81d1ad3bbE
          (local.get $7)
         )
        )
        (block $block28
         (if
          (i32.ne
           (local.get $12)
           (i32.const 1)
          )
          (then
           (br_if $block28
            (i32.ge_s
             (i32.load offset=16
              (local.get $7)
             )
             (i32.const -2147483646)
            )
           )
           (block $block29
            (block $block30
             (block $block76
              (if
               (i32.eqz
                (f64.le
                 (f64.abs
                  (f64.sub
                   (local.tee $33
                    (block $block34 (result f64)
                     (block $block33
                      (if
                       (i32.gt_u
                        (local.get $12)
                        (i32.const 2)
                       )
                       (then
                        (br_if $block29
                         (i32.ge_s
                          (i32.load offset=32
                           (local.get $7)
                          )
                          (i32.const -2147483646)
                         )
                        )
                        (local.set $21
                         (i32.load offset=28
                          (local.get $7)
                         )
                        )
                        (local.set $22
                         (i32.load offset=24
                          (local.get $7)
                         )
                        )
                        (call $_RNvXs2_NtNtCsdHhIpgkcIfN_4core3num7dec2fltdNtNtNtB9_3str6traits7FromStr8from_str
                         (local.tee $2
                          (i32.add
                           (local.get $1)
                           (i32.const 48)
                          )
                         )
                         (i32.load offset=40
                          (local.get $7)
                         )
                         (i32.load offset=44
                          (local.get $7)
                         )
                        )
                        (br_if $block30
                         (i32.eq
                          (i32.load8_u offset=48
                           (local.get $1)
                          )
                          (i32.const 1)
                         )
                        )
                        (local.set $34
                         (f64.load offset=56
                          (local.get $1)
                         )
                        )
                        (br_if $block31
                         (i32.eq
                          (call $__clock_gettime
                           (local.get $2)
                          )
                          (i32.const -1)
                         )
                        )
                        (br_if $block32
                         (i32.ge_u
                          (local.tee $23
                           (i32.load offset=56
                            (local.get $1)
                           )
                          )
                          (i32.const 1000000000)
                         )
                        )
                        (i64.store
                         (local.get $1)
                         (i64.const 0)
                        )
                        (local.set $31
                         (i64.load offset=48
                          (local.get $1)
                         )
                        )
                        (br_if $block33
                         (local.get $18)
                        )
                        (br $block34
                         (f64.const 0)
                        )
                       )
                      )
                      (call $_RNvNtCsdHhIpgkcIfN_4core9panicking18panic_bounds_check
                       (i32.const 2)
                       (i32.const 2)
                       (i32.const 1051940)
                      )
                      (unreachable)
                     )
                     (local.set $8
                      (i32.sub
                       (local.tee $24
                        (i32.and
                         (i32.add
                          (local.get $1)
                          (i32.const 51)
                         )
                         (i32.const -4)
                        )
                       )
                       (i32.add
                        (local.get $1)
                        (i32.const 48)
                       )
                      )
                     )
                     (local.set $32
                      (i64.load
                       (i32.const 1071336)
                      )
                     )
                     (local.set $30
                      (i64.load
                       (i32.const 1051848)
                      )
                     )
                     (local.set $9
                      (i32.or
                       (i32.add
                        (local.get $1)
                        (i32.const 432)
                       )
                       (i32.const 1)
                      )
                     )
                     (local.set $20
                      (i32.add
                       (local.get $1)
                       (i32.const 456)
                      )
                     )
                     (loop $label17
                      (i32.store offset=52
                       (local.get $1)
                       (local.get $21)
                      )
                      (i32.store offset=48
                       (local.get $1)
                       (local.get $22)
                      )
                      (local.set $2
                       (i32.load offset=48
                        (local.get $1)
                       )
                      )
                      (local.set $3
                       (i32.load offset=52
                        (local.get $1)
                       )
                      )
                      (i32.store
                       (local.get $20)
                       (i32.const 0)
                      )
                      (i32.store16 offset=4
                       (local.get $20)
                       (i32.const 0)
                      )
                      (i64.store offset=448 align=4
                       (local.get $1)
                       (i64.const 1881195675648)
                      )
                      (i32.store8 offset=456
                       (local.get $1)
                       (i32.const 1)
                      )
                      (i32.store offset=32
                       (local.get $1)
                       (i32.add
                        (local.get $1)
                        (i32.const 448)
                       )
                      )
                      (block $block43
                       (block $block44
                        (block $block39
                         (block $block36
                          (block $block37
                           (block $block38
                            (block $block35
                             (if
                              (i32.le_u
                               (local.get $3)
                               (i32.const 383)
                              )
                              (then
                               (if
                                (local.get $3)
                                (then
                                 (memory.copy
                                  (i32.add
                                   (local.get $1)
                                   (i32.const 48)
                                  )
                                  (local.get $2)
                                  (local.get $3)
                                 )
                                )
                               )
                               (i32.store8
                                (i32.add
                                 (local.tee $2
                                  (i32.add
                                   (local.get $1)
                                   (i32.const 48)
                                  )
                                 )
                                 (local.get $3)
                                )
                                (i32.const 0)
                               )
                               (if
                                (i32.ge_u
                                 (local.get $3)
                                 (i32.const 7)
                                )
                                (then
                                 (br_if $block35
                                  (i32.eq
                                   (local.get $2)
                                   (local.get $24)
                                  )
                                 )
                                 (local.set $2
                                  (i32.const 0)
                                 )
                                 (loop $label6
                                  (br_if $block36
                                   (i32.eqz
                                    (i32.load8_u
                                     (i32.add
                                      (i32.add
                                       (local.get $1)
                                       (i32.const 48)
                                      )
                                      (local.get $2)
                                     )
                                    )
                                   )
                                  )
                                  (br_if $label6
                                   (i32.ne
                                    (local.get $8)
                                    (local.tee $2
                                     (i32.add
                                      (local.get $2)
                                      (i32.const 1)
                                     )
                                    )
                                   )
                                  )
                                 )
                                 (br_if $block37
                                  (i32.lt_u
                                   (local.tee $4
                                    (i32.sub
                                     (local.get $3)
                                     (i32.const 7)
                                    )
                                   )
                                   (local.tee $2
                                    (local.get $8)
                                   )
                                  )
                                 )
                                 (br $block38)
                                )
                               )
                               (if
                                (i32.eqz
                                 (i32.load8_u offset=48
                                  (local.get $1)
                                 )
                                )
                                (then
                                 (local.set $2
                                  (i32.const 0)
                                 )
                                 (br $block36)
                                )
                               )
                               (br_if $block39
                                (i32.eqz
                                 (local.get $3)
                                )
                               )
                               (if
                                (i32.eqz
                                 (i32.load8_u offset=49
                                  (local.get $1)
                                 )
                                )
                                (then
                                 (local.set $2
                                  (i32.const 1)
                                 )
                                 (br $block36)
                                )
                               )
                               (br_if $block39
                                (i32.eq
                                 (local.get $3)
                                 (i32.const 1)
                                )
                               )
                               (if
                                (i32.eqz
                                 (i32.load8_u offset=50
                                  (local.get $1)
                                 )
                                )
                                (then
                                 (local.set $2
                                  (i32.const 2)
                                 )
                                 (br $block36)
                                )
                               )
                               (br_if $block39
                                (i32.eq
                                 (local.get $3)
                                 (i32.const 2)
                                )
                               )
                               (if
                                (i32.eqz
                                 (i32.load8_u offset=51
                                  (local.get $1)
                                 )
                                )
                                (then
                                 (local.set $2
                                  (i32.const 3)
                                 )
                                 (br $block36)
                                )
                               )
                               (br_if $block39
                                (i32.eq
                                 (local.get $3)
                                 (i32.const 3)
                                )
                               )
                               (if
                                (i32.eqz
                                 (i32.load8_u offset=52
                                  (local.get $1)
                                 )
                                )
                                (then
                                 (local.set $2
                                  (i32.const 4)
                                 )
                                 (br $block36)
                                )
                               )
                               (br_if $block39
                                (i32.eq
                                 (local.get $3)
                                 (i32.const 4)
                                )
                               )
                               (if
                                (i32.eqz
                                 (i32.load8_u offset=53
                                  (local.get $1)
                                 )
                                )
                                (then
                                 (local.set $2
                                  (i32.const 5)
                                 )
                                 (br $block36)
                                )
                               )
                               (br_if $block39
                                (i32.eq
                                 (local.get $3)
                                 (i32.const 5)
                                )
                               )
                               (br_if $block39
                                (i32.load8_u offset=54
                                 (local.get $1)
                                )
                               )
                               (local.set $2
                                (i32.const 6)
                               )
                               (br $block36)
                              )
                             )
                             (local.set $14
                              (i32.add
                               (local.get $1)
                               (i32.const 432)
                              )
                             )
                             (local.set $11
                              (i32.add
                               (local.get $1)
                               (i32.const 32)
                              )
                             )
                             (local.set $5
                              (i32.const 0)
                             )
                             (block $block42
                              (block $block40
                               (block $block41
                                (if
                                 (i32.ge_s
                                  (local.tee $3
                                   (i32.add
                                    (local.tee $4
                                     (local.get $3)
                                    )
                                    (i32.const 1)
                                   )
                                  )
                                  (i32.const 0)
                                 )
                                 (then
                                  (if
                                   (local.tee $6
                                    (call $dlmalloc
                                     (local.get $3)
                                    )
                                   )
                                   (then
                                    (if
                                     (local.get $4)
                                     (then
                                      (memory.copy
                                       (local.get $6)
                                       (local.get $2)
                                       (local.get $4)
                                      )
                                     )
                                    )
                                    (if
                                     (i32.ne
                                      (local.get $2)
                                      (local.tee $3
                                       (i32.and
                                        (i32.add
                                         (local.get $2)
                                         (i32.const 3)
                                        )
                                        (i32.const -4)
                                       )
                                      )
                                     )
                                     (then
                                      (local.set $5
                                       (i32.sub
                                        (local.get $3)
                                        (local.get $2)
                                       )
                                      )
                                      (local.set $10
                                       (i32.sub
                                        (local.get $2)
                                        (local.get $3)
                                       )
                                      )
                                      (local.set $3
                                       (local.get $2)
                                      )
                                      (loop $label7
                                       (br_if $block40
                                        (i32.eqz
                                         (i32.load8_u
                                          (local.get $3)
                                         )
                                        )
                                       )
                                       (local.set $3
                                        (i32.add
                                         (local.get $3)
                                         (i32.const 1)
                                        )
                                       )
                                       (br_if $label7
                                        (local.tee $10
                                         (i32.add
                                          (local.get $10)
                                          (i32.const 1)
                                         )
                                        )
                                       )
                                      )
                                     )
                                    )
                                    (local.set $3
                                     (i32.sub
                                      (local.get $4)
                                      (i32.const 8)
                                     )
                                    )
                                    (loop $label8
                                     (br_if $block41
                                      (i32.ne
                                       (i32.and
                                        (i32.and
                                         (i32.or
                                          (i32.sub
                                           (i32.const 16843008)
                                           (local.tee $16
                                            (i32.load
                                             (local.tee $10
                                              (i32.add
                                               (local.get $2)
                                               (local.get $5)
                                              )
                                             )
                                            )
                                           )
                                          )
                                          (local.get $16)
                                         )
                                         (i32.or
                                          (i32.sub
                                           (i32.const 16843008)
                                           (local.tee $10
                                            (i32.load
                                             (i32.add
                                              (local.get $10)
                                              (i32.const 4)
                                             )
                                            )
                                           )
                                          )
                                          (local.get $10)
                                         )
                                        )
                                        (i32.const -2139062144)
                                       )
                                       (i32.const -2139062144)
                                      )
                                     )
                                     (br_if $label8
                                      (i32.le_u
                                       (local.tee $5
                                        (i32.add
                                         (local.get $5)
                                         (i32.const 8)
                                        )
                                       )
                                       (local.get $3)
                                      )
                                     )
                                    )
                                    (br $block41)
                                   )
                                  )
                                  (call $_RNvNtCsi9YzqDQQz2q_5alloc7raw_vec12handle_error
                                   (i32.const 1)
                                   (local.get $3)
                                  )
                                  (unreachable)
                                 )
                                )
                                (call $_RNvNtCsi9YzqDQQz2q_5alloc7raw_vec17capacity_overflow)
                                (unreachable)
                               )
                               (if
                                (i32.ne
                                 (local.get $4)
                                 (local.get $5)
                                )
                                (then
                                 (local.set $3
                                  (i32.sub
                                   (local.get $4)
                                   (local.get $5)
                                  )
                                 )
                                 (local.set $5
                                  (i32.add
                                   (local.get $2)
                                   (local.get $5)
                                  )
                                 )
                                 (loop $label9
                                  (br_if $block40
                                   (i32.eqz
                                    (i32.load8_u
                                     (local.get $5)
                                    )
                                   )
                                  )
                                  (local.set $5
                                   (i32.add
                                    (local.get $5)
                                    (i32.const 1)
                                   )
                                  )
                                  (br_if $label9
                                   (local.tee $3
                                    (i32.sub
                                     (local.get $3)
                                     (i32.const 1)
                                    )
                                   )
                                  )
                                 )
                                )
                               )
                               (i32.store8
                                (i32.add
                                 (local.get $4)
                                 (local.get $6)
                                )
                                (i32.const 0)
                               )
                               (call $_RNCNvMsi_NtNtNtCset5xJoy1xWQ_3std3sys2fs4unixNtB7_4File4open0Bd_
                                (local.get $14)
                                (i32.load
                                 (local.get $11)
                                )
                                (local.get $6)
                               )
                               (br $block42)
                              )
                              (i64.store align=4
                               (local.get $14)
                               (i64.load
                                (i32.const 1071336)
                               )
                              )
                             )
                             (call $dlfree
                              (local.get $6)
                             )
                             (br $block43)
                            )
                            (local.set $4
                             (i32.sub
                              (local.get $3)
                              (i32.const 7)
                             )
                            )
                            (local.set $2
                             (i32.const 0)
                            )
                           )
                           (loop $label10
                            (br_if $block37
                             (i32.ne
                              (i32.and
                               (i32.and
                                (i32.or
                                 (i32.sub
                                  (i32.const 16843008)
                                  (local.tee $6
                                   (i32.load
                                    (local.tee $5
                                     (i32.add
                                      (i32.add
                                       (local.get $1)
                                       (i32.const 48)
                                      )
                                      (local.get $2)
                                     )
                                    )
                                   )
                                  )
                                 )
                                 (local.get $6)
                                )
                                (i32.or
                                 (i32.sub
                                  (i32.const 16843008)
                                  (local.tee $5
                                   (i32.load
                                    (i32.add
                                     (local.get $5)
                                     (i32.const 4)
                                    )
                                   )
                                  )
                                 )
                                 (local.get $5)
                                )
                               )
                               (i32.const -2139062144)
                              )
                              (i32.const -2139062144)
                             )
                            )
                            (br_if $label10
                             (i32.le_u
                              (local.tee $2
                               (i32.add
                                (local.get $2)
                                (i32.const 8)
                               )
                              )
                              (local.get $4)
                             )
                            )
                           )
                          )
                          (br_if $block39
                           (i32.eq
                            (local.tee $4
                             (i32.add
                              (local.get $3)
                              (i32.const 1)
                             )
                            )
                            (local.get $2)
                           )
                          )
                          (local.set $4
                           (i32.sub
                            (local.get $4)
                            (local.get $2)
                           )
                          )
                          (local.set $6
                           (i32.add
                            (i32.add
                             (local.get $1)
                             (i32.const 48)
                            )
                            (local.get $2)
                           )
                          )
                          (local.set $5
                           (i32.const 0)
                          )
                          (loop $label11
                           (if
                            (i32.load8_u
                             (i32.add
                              (local.get $5)
                              (local.get $6)
                             )
                            )
                            (then
                             (br_if $label11
                              (i32.ne
                               (local.get $4)
                               (local.tee $5
                                (i32.add
                                 (local.get $5)
                                 (i32.const 1)
                                )
                               )
                              )
                             )
                             (br $block39)
                            )
                           )
                          )
                          (local.set $2
                           (i32.add
                            (local.get $2)
                            (local.get $5)
                           )
                          )
                         )
                         (br_if $block44
                          (i32.eq
                           (local.get $2)
                           (local.get $3)
                          )
                         )
                        )
                        (i64.store offset=432
                         (local.get $1)
                         (local.get $32)
                        )
                        (br $block43)
                       )
                       (call $_RNCNvMsi_NtNtNtCset5xJoy1xWQ_3std3sys2fs4unixNtB7_4File4open0Bd_
                        (i32.add
                         (local.get $1)
                         (i32.const 432)
                        )
                        (i32.add
                         (local.get $1)
                         (i32.const 448)
                        )
                        (i32.add
                         (local.get $1)
                         (i32.const 48)
                        )
                       )
                      )
                      (block $block75
                       (block $block46
                        (local.set $16
                         (block $block45 (result i32)
                          (if
                           (i32.eq
                            (i32.load8_u offset=432
                             (local.get $1)
                            )
                            (i32.const 4)
                           )
                           (then
                            (br $block45
                             (i32.load offset=436
                              (local.get $1)
                             )
                            )
                           )
                          )
                          (br_if $block46
                           (i64.ne
                            (i64.and
                             (local.tee $29
                              (i64.load offset=432
                               (local.get $1)
                              )
                             )
                             (i64.const 255)
                            )
                            (i64.const 4)
                           )
                          )
                          (i32.wrap_i64
                           (i64.shr_u
                            (local.get $29)
                            (i64.const 32)
                           )
                          )
                         )
                        )
                        (if
                         (local.tee $14
                          (call $dlmalloc
                           (i32.const 8192)
                          )
                         )
                         (then
                          (local.set $33
                           (f64.const 0)
                          )
                          (local.set $2
                           (i32.const 0)
                          )
                          (local.set $5
                           (i32.const 0)
                          )
                          (loop $label15
                           (i64.store offset=448 align=4
                            (local.get $1)
                            (i64.const 4294967296)
                           )
                           (local.set $6
                            (i32.const 0)
                           )
                           (block $block74
                            (br_if $block75
                             (i32.eqz
                              (block (result i32)
                               (local.set $scratch_38
                                (block $block73 (result i32)
                                 (block $block72
                                  (loop $label13
                                   (i32.store offset=456
                                    (local.get $1)
                                    (local.get $6)
                                   )
                                   (block $block48
                                    (loop $label14
                                     (block $block71
                                      (i32.store offset=432
                                       (local.get $1)
                                       (i32.const 0)
                                      )
                                      (block $block60
                                       (local.set $6
                                        (i32.add
                                         (if (result i32)
                                          (i32.gt_u
                                           (local.tee $11
                                            (block $block67 (result i32)
                                             (block $block63
                                              (block $block68
                                               (block $block62
                                                (block $block66
                                                 (block $block61
                                                  (block $block64
                                                   (block $block65
                                                    (local.set $29
                                                     (block $block58 (result i64)
                                                      (block $block50
                                                       (block $block56
                                                        (block $block57
                                                         (block $block47
                                                          (if
                                                           (i32.ge_u
                                                            (local.get $2)
                                                            (local.get $5)
                                                           )
                                                           (then
                                                            (local.set $2
                                                             (i32.const 0)
                                                            )
                                                            (br_if $block47
                                                             (i32.eq
                                                              (local.tee $5
                                                               (call $read
                                                                (local.get $16)
                                                                (local.get $14)
                                                                (i32.const 8192)
                                                               )
                                                              )
                                                              (i32.const -1)
                                                             )
                                                            )
                                                           )
                                                          )
                                                          (local.set $3
                                                           (i32.add
                                                            (local.get $2)
                                                            (local.get $14)
                                                           )
                                                          )
                                                          (if
                                                           (i32.eqz
                                                            (local.tee $4
                                                             (i32.ne
                                                              (local.get $2)
                                                              (local.get $5)
                                                             )
                                                            )
                                                           )
                                                           (then
                                                            (if
                                                             (local.get $4)
                                                             (then
                                                              (memory.copy
                                                               (i32.add
                                                                (local.get $1)
                                                                (i32.const 432)
                                                               )
                                                               (local.get $3)
                                                               (local.get $4)
                                                              )
                                                             )
                                                            )
                                                            (local.set $2
                                                             (select
                                                              (local.get $5)
                                                              (local.tee $2
                                                               (i32.add
                                                                (local.get $2)
                                                                (local.get $4)
                                                               )
                                                              )
                                                              (i32.gt_u
                                                               (local.get $2)
                                                               (local.get $5)
                                                              )
                                                             )
                                                            )
                                                            (br $block48)
                                                           )
                                                          )
                                                          (i32.store8 offset=432
                                                           (local.get $1)
                                                           (local.tee $3
                                                            (i32.load8_s
                                                             (local.get $3)
                                                            )
                                                           )
                                                          )
                                                          (block $block49
                                                           (if
                                                            (i32.ge_s
                                                             (local.get $3)
                                                             (i32.const 0)
                                                            )
                                                            (then
                                                             (local.set $10
                                                              (i32.const 1)
                                                             )
                                                             (br $block49)
                                                            )
                                                           )
                                                           (if
                                                            (i32.lt_u
                                                             (i32.and
                                                              (i32.add
                                                               (local.get $3)
                                                               (i32.const 62)
                                                              )
                                                              (i32.const 255)
                                                             )
                                                             (i32.const 30)
                                                            )
                                                            (then
                                                             (local.set $10
                                                              (i32.const 2)
                                                             )
                                                             (br $block49)
                                                            )
                                                           )
                                                           (if
                                                            (i32.eq
                                                             (i32.and
                                                              (local.get $3)
                                                              (i32.const -16)
                                                             )
                                                             (i32.const -32)
                                                            )
                                                            (then
                                                             (local.set $10
                                                              (i32.const 3)
                                                             )
                                                             (br $block49)
                                                            )
                                                           )
                                                           (local.set $10
                                                            (i32.const 4)
                                                           )
                                                           (br_if $block50
                                                            (i32.gt_u
                                                             (i32.and
                                                              (i32.add
                                                               (local.get $3)
                                                               (i32.const 16)
                                                              )
                                                              (i32.const 255)
                                                             )
                                                             (i32.const 4)
                                                            )
                                                           )
                                                          )
                                                          (local.set $2
                                                           (block $block53 (result i32)
                                                            (block $block55
                                                             (if
                                                              (i32.gt_u
                                                               (local.tee $6
                                                                (i32.sub
                                                                 (local.get $10)
                                                                 (i32.const 1)
                                                                )
                                                               )
                                                               (i32.sub
                                                                (local.get $5)
                                                                (local.tee $2
                                                                 (select
                                                                  (local.get $5)
                                                                  (local.tee $2
                                                                   (i32.add
                                                                    (local.get $2)
                                                                    (local.get $4)
                                                                   )
                                                                  )
                                                                  (i32.gt_u
                                                                   (local.get $2)
                                                                   (local.get $5)
                                                                  )
                                                                 )
                                                                )
                                                               )
                                                              )
                                                              (then
                                                               (local.set $4
                                                                (local.get $9)
                                                               )
                                                               (loop $label12
                                                                (block $block54
                                                                 (block $block51
                                                                  (if
                                                                   (i32.ge_u
                                                                    (local.get $2)
                                                                    (local.get $5)
                                                                   )
                                                                   (then
                                                                    (local.set $2
                                                                     (i32.const 0)
                                                                    )
                                                                    (br_if $block51
                                                                     (i32.eq
                                                                      (local.tee $5
                                                                       (call $read
                                                                        (local.get $16)
                                                                        (local.get $14)
                                                                        (i32.const 8192)
                                                                       )
                                                                      )
                                                                      (i32.const -1)
                                                                     )
                                                                    )
                                                                   )
                                                                  )
                                                                  (local.set $3
                                                                   (i32.add
                                                                    (local.get $2)
                                                                    (local.get $14)
                                                                   )
                                                                  )
                                                                  (block $block52
                                                                   (if
                                                                    (i32.eq
                                                                     (local.tee $11
                                                                      (select
                                                                       (local.tee $11
                                                                        (i32.sub
                                                                         (local.get $5)
                                                                         (local.get $2)
                                                                        )
                                                                       )
                                                                       (local.get $6)
                                                                       (i32.gt_u
                                                                        (local.get $6)
                                                                        (local.get $11)
                                                                       )
                                                                      )
                                                                     )
                                                                     (i32.const 1)
                                                                    )
                                                                    (then
                                                                     (i32.store8
                                                                      (local.get $4)
                                                                      (i32.load8_u
                                                                       (local.get $3)
                                                                      )
                                                                     )
                                                                     (br $block52)
                                                                    )
                                                                   )
                                                                   (br_if $block52
                                                                    (i32.eqz
                                                                     (local.get $11)
                                                                    )
                                                                   )
                                                                   (memory.copy
                                                                    (local.get $4)
                                                                    (local.get $3)
                                                                    (local.get $11)
                                                                   )
                                                                  )
                                                                  (local.set $3
                                                                   (select
                                                                    (local.get $5)
                                                                    (local.tee $3
                                                                     (i32.add
                                                                      (local.get $2)
                                                                      (local.get $11)
                                                                     )
                                                                    )
                                                                    (i32.gt_u
                                                                     (local.get $3)
                                                                     (local.get $5)
                                                                    )
                                                                   )
                                                                  )
                                                                  (if
                                                                   (i32.eq
                                                                    (local.get $2)
                                                                    (local.get $5)
                                                                   )
                                                                   (then
                                                                    (local.set $29
                                                                     (local.get $30)
                                                                    )
                                                                    (br $block53
                                                                     (local.get $3)
                                                                    )
                                                                   )
                                                                  )
                                                                  (local.set $4
                                                                   (i32.add
                                                                    (local.get $4)
                                                                    (local.get $11)
                                                                   )
                                                                  )
                                                                  (local.set $6
                                                                   (i32.sub
                                                                    (local.get $6)
                                                                    (local.get $11)
                                                                   )
                                                                  )
                                                                  (local.set $2
                                                                   (local.get $3)
                                                                  )
                                                                  (br $block54)
                                                                 )
                                                                 (local.set $5
                                                                  (i32.const 0)
                                                                 )
                                                                 (br_if $block55
                                                                  (i32.ne
                                                                   (local.tee $3
                                                                    (i32.load
                                                                     (i32.const 1077468)
                                                                    )
                                                                   )
                                                                   (i32.const 27)
                                                                  )
                                                                 )
                                                                )
                                                                (br_if $label12
                                                                 (local.get $6)
                                                                )
                                                               )
                                                               (br $block56)
                                                              )
                                                             )
                                                             (if
                                                              (local.get $6)
                                                              (then
                                                               (memory.copy
                                                                (local.get $9)
                                                                (i32.add
                                                                 (local.get $2)
                                                                 (local.get $14)
                                                                )
                                                                (local.get $6)
                                                               )
                                                              )
                                                             )
                                                             (local.set $2
                                                              (i32.add
                                                               (local.get $2)
                                                               (local.get $6)
                                                              )
                                                             )
                                                             (br $block56)
                                                            )
                                                            (local.set $29
                                                             (i64.shl
                                                              (i64.extend_i32_u
                                                               (local.get $3)
                                                              )
                                                              (i64.const 32)
                                                             )
                                                            )
                                                            (i32.const 0)
                                                           )
                                                          )
                                                          (br_if $block56
                                                           (i64.eq
                                                            (i64.and
                                                             (local.get $29)
                                                             (i64.const 255)
                                                            )
                                                            (i64.const 4)
                                                           )
                                                          )
                                                          (local.set $30
                                                           (i64.shr_u
                                                            (local.get $29)
                                                            (i64.const 32)
                                                           )
                                                          )
                                                          (br $block57)
                                                         )
                                                         (local.set $29
                                                          (i64.shl
                                                           (local.tee $30
                                                            (i64.load32_u
                                                             (i32.const 1077468)
                                                            )
                                                           )
                                                           (i64.const 32)
                                                          )
                                                         )
                                                        )
                                                        (br $block58
                                                         (i64.or
                                                          (i64.and
                                                           (local.get $29)
                                                           (i64.const 4294967295)
                                                          )
                                                          (i64.shl
                                                           (local.get $30)
                                                           (i64.const 32)
                                                          )
                                                         )
                                                        )
                                                       )
                                                       (call $_RNvNtNtCsdHhIpgkcIfN_4core3str8converts9from_utf8
                                                        (i32.add
                                                         (local.get $1)
                                                         (i32.const 48)
                                                        )
                                                        (i32.add
                                                         (local.get $1)
                                                         (i32.const 432)
                                                        )
                                                        (local.get $10)
                                                       )
                                                       (br_if $block50
                                                        (i32.eq
                                                         (i32.load offset=48
                                                          (local.get $1)
                                                         )
                                                         (i32.const 1)
                                                        )
                                                       )
                                                       (br_if $block48
                                                        (i32.eqz
                                                         (i32.load offset=56
                                                          (local.get $1)
                                                         )
                                                        )
                                                       )
                                                       (br_if $block60
                                                        (i32.eq
                                                         (local.tee $4
                                                          (block $block59 (result i32)
                                                           (if
                                                            (i32.ge_s
                                                             (local.tee $4
                                                              (i32.load8_s
                                                               (local.tee $3
                                                                (i32.load offset=52
                                                                 (local.get $1)
                                                                )
                                                               )
                                                              )
                                                             )
                                                             (i32.const 0)
                                                            )
                                                            (then
                                                             (br $block59
                                                              (i32.and
                                                               (local.get $4)
                                                               (i32.const 255)
                                                              )
                                                             )
                                                            )
                                                           )
                                                           (drop
                                                            (br_if $block59
                                                             (i32.or
                                                              (local.tee $10
                                                               (i32.and
                                                                (i32.load8_u offset=1
                                                                 (local.get $3)
                                                                )
                                                                (i32.const 63)
                                                               )
                                                              )
                                                              (i32.shl
                                                               (local.tee $6
                                                                (i32.and
                                                                 (local.get $4)
                                                                 (i32.const 31)
                                                                )
                                                               )
                                                               (i32.const 6)
                                                              )
                                                             )
                                                             (i32.le_u
                                                              (local.get $4)
                                                              (i32.const -33)
                                                             )
                                                            )
                                                           )
                                                           (drop
                                                            (br_if $block59
                                                             (i32.or
                                                              (local.tee $10
                                                               (i32.or
                                                                (i32.and
                                                                 (i32.load8_u offset=2
                                                                  (local.get $3)
                                                                 )
                                                                 (i32.const 63)
                                                                )
                                                                (i32.shl
                                                                 (local.get $10)
                                                                 (i32.const 6)
                                                                )
                                                               )
                                                              )
                                                              (i32.shl
                                                               (local.get $6)
                                                               (i32.const 12)
                                                              )
                                                             )
                                                             (i32.lt_u
                                                              (local.get $4)
                                                              (i32.const -16)
                                                             )
                                                            )
                                                           )
                                                           (i32.or
                                                            (i32.and
                                                             (i32.shl
                                                              (local.get $6)
                                                              (i32.const 18)
                                                             )
                                                             (i32.const 1835008)
                                                            )
                                                            (i32.or
                                                             (i32.and
                                                              (i32.load8_u offset=3
                                                               (local.get $3)
                                                              )
                                                              (i32.const 63)
                                                             )
                                                             (i32.shl
                                                              (local.get $10)
                                                              (i32.const 6)
                                                             )
                                                            )
                                                           )
                                                          )
                                                         )
                                                         (i32.const 32)
                                                        )
                                                       )
                                                       (br_if $block48
                                                        (i32.eq
                                                         (local.get $4)
                                                         (i32.const 1114112)
                                                        )
                                                       )
                                                       (br_if $block60
                                                        (i32.lt_u
                                                         (i32.sub
                                                          (local.get $4)
                                                          (i32.const 9)
                                                         )
                                                         (i32.const 5)
                                                        )
                                                       )
                                                       (br_if $block61
                                                        (local.tee $25
                                                         (i32.lt_u
                                                          (local.get $4)
                                                          (i32.const 128)
                                                         )
                                                        )
                                                       )
                                                       (br_table $block62 $block63 $block63 $block63 $block63 $block63 $block63 $block63 $block63 $block63 $block64 $block63 $block63 $block63 $block63 $block63 $block63 $block63 $block63 $block63 $block63 $block63 $block63 $block63 $block63 $block63 $block65 $block66
                                                        (i32.sub
                                                         (local.tee $3
                                                          (i32.shr_u
                                                           (local.get $4)
                                                           (i32.const 8)
                                                          )
                                                         )
                                                         (i32.const 22)
                                                        )
                                                       )
                                                      )
                                                      (i64.const 5377)
                                                     )
                                                    )
                                                    (if
                                                     (i32.load offset=448
                                                      (local.get $1)
                                                     )
                                                     (then
                                                      (call $dlfree
                                                       (i32.load offset=452
                                                        (local.get $1)
                                                       )
                                                      )
                                                     )
                                                    )
                                                    (call $dlfree
                                                     (local.get $14)
                                                    )
                                                    (call $close
                                                     (local.get $16)
                                                    )
                                                    (br $block46)
                                                   )
                                                   (br_if $block63
                                                    (i32.ne
                                                     (local.get $4)
                                                     (i32.const 12288)
                                                    )
                                                   )
                                                   (br $block60)
                                                  )
                                                  (br_if $block63
                                                   (i32.eqz
                                                    (i32.and
                                                     (i32.load8_u offset=1069828
                                                      (i32.and
                                                       (local.get $4)
                                                       (i32.const 255)
                                                      )
                                                     )
                                                     (i32.const 2)
                                                    )
                                                   )
                                                  )
                                                  (br $block60)
                                                 )
                                                 (local.set $3
                                                  (i32.load offset=456
                                                   (local.get $1)
                                                  )
                                                 )
                                                 (br $block67
                                                  (i32.const 1)
                                                 )
                                                )
                                                (br_if $block68
                                                 (i32.eqz
                                                  (local.get $3)
                                                 )
                                                )
                                                (br $block63)
                                               )
                                               (br_if $block63
                                                (i32.ne
                                                 (local.get $4)
                                                 (i32.const 5760)
                                                )
                                               )
                                               (br $block60)
                                              )
                                              (br_if $block60
                                               (i32.and
                                                (i32.load8_u offset=1069828
                                                 (i32.and
                                                  (local.get $4)
                                                  (i32.const 255)
                                                 )
                                                )
                                                (i32.const 1)
                                               )
                                              )
                                             )
                                             (local.set $3
                                              (i32.load offset=456
                                               (local.get $1)
                                              )
                                             )
                                             (drop
                                              (br_if $block67
                                               (i32.const 2)
                                               (i32.lt_u
                                                (local.get $4)
                                                (i32.const 2048)
                                               )
                                              )
                                             )
                                             (select
                                              (i32.const 3)
                                              (i32.const 4)
                                              (i32.lt_u
                                               (local.get $4)
                                               (i32.const 65536)
                                              )
                                             )
                                            )
                                           )
                                           (i32.sub
                                            (i32.load offset=448
                                             (local.get $1)
                                            )
                                            (local.get $3)
                                           )
                                          )
                                          (then
                                           (global.set $__stack_pointer
                                            (local.tee $10
                                             (i32.sub
                                              (global.get $__stack_pointer)
                                              (i32.const 16)
                                             )
                                            )
                                           )
                                           (local.set $6
                                            (i32.add
                                             (local.get $10)
                                             (i32.const 4)
                                            )
                                           )
                                           (local.set $19
                                            (local.tee $13
                                             (i32.load
                                              (local.tee $17
                                               (i32.add
                                                (local.get $1)
                                                (i32.const 448)
                                               )
                                              )
                                             )
                                            )
                                           )
                                           (local.set $26
                                            (i32.load offset=4
                                             (local.get $17)
                                            )
                                           )
                                           (block $block70
                                            (if
                                             (i32.ge_s
                                              (local.tee $13
                                               (select
                                                (i32.const 8)
                                                (local.tee $13
                                                 (select
                                                  (local.tee $27
                                                   (i32.add
                                                    (local.get $3)
                                                    (local.get $11)
                                                   )
                                                  )
                                                  (local.tee $13
                                                   (i32.shl
                                                    (local.get $13)
                                                    (i32.const 1)
                                                   )
                                                  )
                                                  (i32.lt_u
                                                   (local.get $13)
                                                   (local.get $27)
                                                  )
                                                 )
                                                )
                                                (i32.le_u
                                                 (local.get $13)
                                                 (i32.const 8)
                                                )
                                               )
                                              )
                                              (i32.const 0)
                                             )
                                             (then
                                              (if
                                               (i32.eqz
                                                (local.tee $19
                                                 (block $block69 (result i32)
                                                  (if
                                                   (local.get $19)
                                                   (then
                                                    (br $block69
                                                     (call $realloc
                                                      (local.get $26)
                                                      (local.get $13)
                                                     )
                                                    )
                                                   )
                                                  )
                                                  (call $dlmalloc
                                                   (local.get $13)
                                                  )
                                                 )
                                                )
                                               )
                                               (then
                                                (i32.store offset=8
                                                 (local.get $6)
                                                 (local.get $13)
                                                )
                                                (i32.store offset=4
                                                 (local.get $6)
                                                 (i32.const 1)
                                                )
                                                (i32.store
                                                 (local.get $6)
                                                 (i32.const 1)
                                                )
                                                (br $block70)
                                               )
                                              )
                                              (i32.store offset=8
                                               (local.get $6)
                                               (local.get $13)
                                              )
                                              (i32.store offset=4
                                               (local.get $6)
                                               (local.get $19)
                                              )
                                              (i32.store
                                               (local.get $6)
                                               (i32.const 0)
                                              )
                                              (br $block70)
                                             )
                                            )
                                            (i32.store offset=4
                                             (local.get $6)
                                             (i32.const 0)
                                            )
                                            (i32.store
                                             (local.get $6)
                                             (i32.const 1)
                                            )
                                           )
                                           (if
                                            (i32.eq
                                             (i32.load offset=4
                                              (local.get $10)
                                             )
                                             (i32.const 1)
                                            )
                                            (then
                                             (call $_RNvNtCsi9YzqDQQz2q_5alloc7raw_vec12handle_error
                                              (i32.load offset=8
                                               (local.get $10)
                                              )
                                              (i32.load offset=12
                                               (local.get $10)
                                              )
                                             )
                                             (unreachable)
                                            )
                                           )
                                           (local.set $6
                                            (i32.load offset=8
                                             (local.get $10)
                                            )
                                           )
                                           (i32.store
                                            (local.get $17)
                                            (local.get $13)
                                           )
                                           (i32.store offset=4
                                            (local.get $17)
                                            (local.get $6)
                                           )
                                           (global.set $__stack_pointer
                                            (i32.add
                                             (local.get $10)
                                             (i32.const 16)
                                            )
                                           )
                                           (i32.load offset=456
                                            (local.get $1)
                                           )
                                          )
                                          (else
                                           (local.get $3)
                                          )
                                         )
                                         (i32.load offset=452
                                          (local.get $1)
                                         )
                                        )
                                       )
                                       (br_if $block71
                                        (local.get $25)
                                       )
                                       (local.set $10
                                        (i32.or
                                         (i32.and
                                          (local.get $4)
                                          (i32.const 63)
                                         )
                                         (i32.const -128)
                                        )
                                       )
                                       (local.set $13
                                        (i32.shr_u
                                         (local.get $4)
                                         (i32.const 6)
                                        )
                                       )
                                       (if
                                        (i32.lt_u
                                         (local.get $4)
                                         (i32.const 2048)
                                        )
                                        (then
                                         (i32.store8 offset=1
                                          (local.get $6)
                                          (local.get $10)
                                         )
                                         (i32.store8
                                          (local.get $6)
                                          (i32.or
                                           (local.get $13)
                                           (i32.const 192)
                                          )
                                         )
                                         (local.set $6
                                          (i32.add
                                           (local.get $3)
                                           (local.get $11)
                                          )
                                         )
                                         (br $label13)
                                        )
                                       )
                                       (local.set $17
                                        (i32.shr_u
                                         (local.get $4)
                                         (i32.const 12)
                                        )
                                       )
                                       (local.set $13
                                        (i32.or
                                         (i32.and
                                          (local.get $13)
                                          (i32.const 63)
                                         )
                                         (i32.const -128)
                                        )
                                       )
                                       (if
                                        (i32.le_u
                                         (local.get $4)
                                         (i32.const 65535)
                                        )
                                        (then
                                         (i32.store8 offset=2
                                          (local.get $6)
                                          (local.get $10)
                                         )
                                         (i32.store8 offset=1
                                          (local.get $6)
                                          (local.get $13)
                                         )
                                         (i32.store8
                                          (local.get $6)
                                          (i32.or
                                           (local.get $17)
                                           (i32.const 224)
                                          )
                                         )
                                         (local.set $6
                                          (i32.add
                                           (local.get $3)
                                           (local.get $11)
                                          )
                                         )
                                         (br $label13)
                                        )
                                       )
                                       (i32.store8 offset=3
                                        (local.get $6)
                                        (local.get $10)
                                       )
                                       (i32.store8 offset=2
                                        (local.get $6)
                                        (local.get $13)
                                       )
                                       (i32.store8 offset=1
                                        (local.get $6)
                                        (i32.or
                                         (i32.and
                                          (local.get $17)
                                          (i32.const 63)
                                         )
                                         (i32.const -128)
                                        )
                                       )
                                       (i32.store8
                                        (local.get $6)
                                        (i32.or
                                         (i32.shr_u
                                          (local.get $4)
                                          (i32.const 18)
                                         )
                                         (i32.const -16)
                                        )
                                       )
                                       (local.set $6
                                        (i32.add
                                         (local.get $3)
                                         (local.get $11)
                                        )
                                       )
                                       (br $label13)
                                      )
                                      (br_if $label14
                                       (i32.eqz
                                        (local.tee $6
                                         (i32.load offset=456
                                          (local.get $1)
                                         )
                                        )
                                       )
                                      )
                                      (br $block72)
                                     )
                                    )
                                    (i32.store8
                                     (local.get $6)
                                     (local.get $4)
                                    )
                                    (local.set $6
                                     (i32.add
                                      (local.get $3)
                                      (local.get $11)
                                     )
                                    )
                                    (br $label13)
                                   )
                                  )
                                  (br_if $block72
                                   (local.tee $6
                                    (i32.load offset=456
                                     (local.get $1)
                                    )
                                   )
                                  )
                                  (br $block73
                                   (i32.const 0)
                                  )
                                 )
                                 (call $_RNvXs2_NtNtCsdHhIpgkcIfN_4core3num7dec2fltdNtNtNtB9_3str6traits7FromStr8from_str
                                  (i32.add
                                   (local.get $1)
                                   (i32.const 48)
                                  )
                                  (i32.load offset=452
                                   (local.get $1)
                                  )
                                  (local.get $6)
                                 )
                                 (br_if $block74
                                  (i32.load8_u offset=48
                                   (local.get $1)
                                  )
                                 )
                                 (local.set $35
                                  (f64.load offset=56
                                   (local.get $1)
                                  )
                                 )
                                 (i32.const 1)
                                )
                               )
                               (if
                                (i32.load offset=448
                                 (local.get $1)
                                )
                                (then
                                 (call $dlfree
                                  (i32.load offset=452
                                   (local.get $1)
                                  )
                                 )
                                )
                               )
                               (local.get $scratch_38)
                              )
                             )
                            )
                            (local.set $33
                             (f64.add
                              (local.get $33)
                              (local.get $35)
                             )
                            )
                            (br $label15)
                           )
                          )
                          (i32.store8 offset=432
                           (local.get $1)
                           (i32.load8_u offset=49
                            (local.get $1)
                           )
                          )
                          (call $_RNvNtCsdHhIpgkcIfN_4core6result13unwrap_failed
                           (i32.const 1051872)
                           (i32.const 18)
                           (i32.add
                            (local.get $1)
                            (i32.const 432)
                           )
                           (i32.const 1051856)
                           (i32.const 1051892)
                          )
                          (unreachable)
                         )
                        )
                        (call $_RNvNtCsi9YzqDQQz2q_5alloc7raw_vec12handle_error
                         (i32.const 1)
                         (i32.const 8192)
                        )
                        (unreachable)
                       )
                       (i64.store align=4
                        (local.get $0)
                        (local.get $29)
                       )
                       (local.set $2
                        (local.get $7)
                       )
                       (loop $label16
                        (call $_ZN4core3ptr47drop_in_place$LT$r7rs_wasm_reference..Datum$GT$17h930252e9aa0d0618E
                         (local.get $2)
                        )
                        (local.set $2
                         (i32.add
                          (local.get $2)
                          (i32.const 16)
                         )
                        )
                        (br_if $label16
                         (local.tee $12
                          (i32.sub
                           (local.get $12)
                           (i32.const 1)
                          )
                         )
                        )
                       )
                       (br_if $block76
                        (local.get $15)
                       )
                       (br $block77)
                      )
                      (call $dlfree
                       (local.get $14)
                      )
                      (call $close
                       (local.get $16)
                      )
                      (f64.store
                       (local.get $1)
                       (local.get $33)
                      )
                      (br_if $label17
                       (i32.ne
                        (local.tee $28
                         (i32.add
                          (local.get $28)
                          (i32.const 1)
                         )
                        )
                        (local.get $18)
                       )
                      )
                     )
                     (f64.load
                      (local.get $1)
                     )
                    )
                   )
                   (local.get $34)
                  )
                 )
                 (f64.const 1e-09)
                )
               )
               (then
                (call $_RNvNtCsdHhIpgkcIfN_4core9panicking5panic
                 (i32.const 1051956)
                 (i32.const 51)
                 (i32.const 1052008)
                )
                (unreachable)
               )
              )
              (f64.store offset=24
               (local.get $1)
               (local.get $33)
              )
              (i32.store offset=20
               (local.get $1)
               (local.get $18)
              )
              (i32.store offset=16
               (local.get $1)
               (i32.const 4)
              )
              (i32.store offset=12
               (local.get $1)
               (i32.const 1052024)
              )
              (br_if $block31
               (i32.eq
                (call $__clock_gettime
                 (local.tee $2
                  (i32.add
                   (local.get $1)
                   (i32.const 48)
                  )
                 )
                )
                (i32.const -1)
               )
              )
              (br_if $block32
               (i32.ge_u
                (local.tee $4
                 (i32.load offset=56
                  (local.get $1)
                 )
                )
                (i32.const 1000000000)
               )
              )
              (local.set $29
               (i64.load offset=48
                (local.get $1)
               )
              )
              (i32.store offset=440
               (local.get $1)
               (local.get $4)
              )
              (i64.store offset=432
               (local.get $1)
               (local.get $29)
              )
              (i32.store offset=456
               (local.get $1)
               (local.get $23)
              )
              (i64.store offset=448
               (local.get $1)
               (local.get $31)
              )
              (call $_RNvMNtNtNtNtCset5xJoy1xWQ_3std3sys3pal4wasi4timeNtB2_8Timespec12sub_timespec
               (local.get $2)
               (i32.add
                (local.get $1)
                (i32.const 432)
               )
               (i32.add
                (local.get $1)
                (i32.const 448)
               )
              )
              (f64.store offset=32
               (local.get $1)
               (select
                (f64.const 0)
                (f64.add
                 (f64.div
                  (f64.convert_i32_u
                   (i32.load offset=64
                    (local.get $1)
                   )
                  )
                  (f64.const 1e9)
                 )
                 (f64.convert_i64_u
                  (i64.load offset=56
                   (local.get $1)
                  )
                 )
                )
                (i32.load offset=48
                 (local.get $1)
                )
               )
              )
              (i64.store offset=48
               (local.get $1)
               (i64.or
                (i64.extend_i32_u
                 (i32.add
                  (local.get $1)
                  (i32.const 24)
                 )
                )
                (i64.const 4294967296)
               )
              )
              (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio6__print
               (i32.const 1051667)
               (local.get $2)
              )
              (i64.store offset=64
               (local.get $1)
               (i64.or
                (i64.extend_i32_u
                 (i32.add
                  (local.get $1)
                  (i32.const 32)
                 )
                )
                (i64.const 4294967296)
               )
              )
              (i64.store offset=56
               (local.get $1)
               (i64.or
                (i64.extend_i32_u
                 (i32.add
                  (local.get $1)
                  (i32.const 20)
                 )
                )
                (i64.const 8589934592)
               )
              )
              (i64.store offset=48
               (local.get $1)
               (i64.or
                (i64.extend_i32_u
                 (i32.add
                  (local.get $1)
                  (i32.const 12)
                 )
                )
                (i64.const 12884901888)
               )
              )
              (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio6__print
               (i32.const 1051765)
               (local.get $2)
              )
              (i32.store8
               (local.get $0)
               (i32.const 4)
              )
              (local.set $2
               (local.get $7)
              )
              (loop $label18
               (call $_ZN4core3ptr47drop_in_place$LT$r7rs_wasm_reference..Datum$GT$17h930252e9aa0d0618E
                (local.get $2)
               )
               (local.set $2
                (i32.add
                 (local.get $2)
                 (i32.const 16)
                )
               )
               (br_if $label18
                (local.tee $12
                 (i32.sub
                  (local.get $12)
                  (i32.const 1)
                 )
                )
               )
              )
              (br_if $block77
               (i32.eqz
                (local.get $15)
               )
              )
             )
             (call $dlfree
              (local.get $7)
             )
             (br $block77)
            )
            (i32.store8 offset=448
             (local.get $1)
             (i32.load8_u offset=49
              (local.get $1)
             )
            )
            (call $_RNvNtCsdHhIpgkcIfN_4core6result13unwrap_failed
             (i32.const 1070284)
             (i32.const 22)
             (i32.add
              (local.get $1)
              (i32.const 448)
             )
             (i32.const 1070268)
             (i32.const 1070308)
            )
            (unreachable)
           )
           (call $_RNvNtCsdHhIpgkcIfN_4core9panicking9panic_fmt
            (i32.const 1070179)
            (i32.const 53)
            (i32.const 1070208)
           )
           (unreachable)
          )
         )
         (call $_RNvNtCsdHhIpgkcIfN_4core9panicking18panic_bounds_check
          (i32.const 1)
          (i32.const 1)
          (i32.const 1051924)
         )
         (unreachable)
        )
        (call $_RNvNtCsdHhIpgkcIfN_4core9panicking9panic_fmt
         (i32.const 1070179)
         (i32.const 53)
         (i32.const 1070208)
        )
        (unreachable)
       )
      )
      (call $_RNvNtCsdHhIpgkcIfN_4core9panicking18panic_bounds_check
       (i32.const 0)
       (i32.const 0)
       (i32.const 1051908)
      )
      (unreachable)
     )
     (i64.store align=4
      (local.get $0)
      (i64.or
       (i64.extend_i32_u
        (local.get $7)
       )
       (i64.shl
        (i64.extend_i32_u
         (local.get $12)
        )
        (i64.const 32)
       )
      )
     )
    )
    (global.set $__stack_pointer
     (i32.add
      (local.get $1)
      (i32.const 464)
     )
    )
    (return)
   )
   (i64.store offset=448
    (local.get $1)
    (i64.shl
     (i64.load32_u
      (i32.const 1077468)
     )
     (i64.const 32)
    )
   )
   (call $_RNvNtCsdHhIpgkcIfN_4core6result13unwrap_failed
    (i32.const 1071568)
    (i32.const 43)
    (i32.add
     (local.get $1)
     (i32.const 448)
    )
    (i32.const 1071728)
    (i32.const 1071760)
   )
   (unreachable)
  )
  (i64.store offset=448
   (local.get $1)
   (i64.const 4602985170599938)
  )
  (call $_RNvNtCsdHhIpgkcIfN_4core6result13unwrap_failed
   (i32.const 1071568)
   (i32.const 43)
   (i32.add
    (local.get $1)
    (i32.const 448)
   )
   (i32.const 1071728)
   (i32.const 1071744)
  )
  (unreachable)
 )
