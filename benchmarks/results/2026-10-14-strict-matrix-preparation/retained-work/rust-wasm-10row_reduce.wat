(func $_ZN6matrix10row_reduce17hf3bb418bb445af8fE (param $0 i32) (param $1 i32) (result i32)
  (local $2 i32)
  (local $3 i32)
  (local $4 i32)
  (local $5 i32)
  (local $6 i32)
  (local $7 i32)
  (local $8 i64)
  (local $9 i64)
  (local $10 i64)
  (local $11 i64)
  (global.set $__stack_pointer
   (local.tee $6
    (i32.sub
     (global.get $__stack_pointer)
     (i32.const 16)
    )
   )
  )
  (i32.store
   (local.get $6)
   (local.get $1)
  )
  (block $block14
   (block $block4
    (block $block1
     (block $block
      (br_if $block
       (i32.eqz
        (local.get $1)
       )
      )
      (block $block15
       (block $block8
        (if
         (i32.load offset=8
          (local.get $1)
         )
         (then
          (br_if $block1
           (i64.eqz
            (local.tee $9
             (i64.load
              (local.get $0)
             )
            )
           )
          )
          (local.set $11
           (i64.sub
            (i64.xor
             (local.get $9)
             (local.tee $8
              (i64.shr_s
               (local.get $9)
               (i64.const 63)
              )
             )
            )
            (local.get $8)
           )
          )
          (loop $label1
           (i32.store offset=4
            (local.get $6)
            (local.get $1)
           )
           (i32.store
            (local.get $6)
            (local.tee $4
             (block $block3 (result i32)
              (block $block2
               (if
                (local.tee $2
                 (i32.load offset=8
                  (local.get $1)
                 )
                )
                (then
                 (br_if $block2
                  (local.tee $4
                   (i32.load offset=12
                    (local.get $1)
                   )
                  )
                 )
                 (br $block3
                  (i32.const 0)
                 )
                )
               )
               (call $_RNvNtCsdHhIpgkcIfN_4core6option13unwrap_failed
                (i32.const 1052124)
               )
               (unreachable)
              )
              (i32.store
               (local.get $4)
               (local.tee $4
                (i32.add
                 (i32.load
                  (local.get $4)
                 )
                 (i32.const 1)
                )
               )
              )
              (br_if $block4
               (i32.eqz
                (local.get $4)
               )
              )
              (local.set $2
               (i32.load offset=8
                (local.get $1)
               )
              )
              (i32.load offset=12
               (local.get $1)
              )
             )
            )
           )
           (block $block5
            (br_if $block5
             (i64.ne
              (local.tee $8
               (i64.load offset=8
                (local.get $2)
               )
              )
              (i64.const -9223372036854775808)
             )
            )
            (br_if $block5
             (i64.ne
              (local.get $9)
              (i64.const -1)
             )
            )
            (call $_RNvNtNtCsdHhIpgkcIfN_4core9panicking11panic_const24panic_const_rem_overflow
             (i32.const 1052420)
            )
            (unreachable)
           )
           (local.set $3
            (block $block10 (result i32)
             (block $block9
              (block $block6
               (block $block7
                (if
                 (i64.ne
                  (local.tee $10
                   (i64.and
                    (i64.shr_s
                     (local.tee $8
                      (i64.rem_s
                       (local.get $8)
                       (local.get $9)
                      )
                     )
                     (i64.const 63)
                    )
                    (local.get $11)
                   )
                  )
                  (i64.sub
                   (i64.const 0)
                   (local.get $8)
                  )
                 )
                 (then
                  (br_if $block6
                   (i32.ge_u
                    (local.tee $3
                     (i32.sub
                      (i32.wrap_i64
                       (i64.add
                        (local.get $8)
                        (local.get $10)
                       )
                      )
                      (i32.const 1)
                     )
                    )
                    (local.tee $7
                     (i32.load offset=16
                      (local.get $0)
                     )
                    )
                   )
                  )
                  (i32.store offset=8
                   (local.get $6)
                   (local.tee $7
                    (call $_ZN6matrix5scale17hcc206908d548ce8fE
                     (local.get $9)
                     (i32.add
                      (local.get $2)
                      (i32.const 16)
                     )
                     (i64.load
                      (i32.add
                       (i32.load offset=12
                        (local.get $0)
                       )
                       (i32.shl
                        (local.get $3)
                        (i32.const 3)
                       )
                      )
                     )
                    )
                   )
                  )
                  (br_if $block7
                   (local.get $4)
                  )
                  (local.set $2
                   (local.get $5)
                  )
                  (br $block8)
                 )
                )
                (br_if $block9
                 (local.tee $3
                  (i32.load offset=16
                   (local.get $2)
                  )
                 )
                )
                (br $block10
                 (i32.const 0)
                )
               )
               (loop $label
                (i32.store offset=12
                 (local.get $6)
                 (local.get $4)
                )
                (block $block11
                 (if
                  (local.tee $2
                   (i32.load offset=8
                    (local.get $4)
                   )
                  )
                  (then
                   (local.set $8
                    (i64.load offset=8
                     (local.get $2)
                    )
                   )
                   (br_if $block11
                    (i64.ne
                     (local.get $9)
                     (i64.const -1)
                    )
                   )
                   (br_if $block11
                    (i64.ne
                     (local.get $8)
                     (i64.const -9223372036854775808)
                    )
                   )
                   (call $_RNvNtNtCsdHhIpgkcIfN_4core9panicking11panic_const24panic_const_rem_overflow
                    (i32.const 1052420)
                   )
                   (unreachable)
                  )
                 )
                 (call $_RNvNtCsdHhIpgkcIfN_4core6option13unwrap_failed
                  (i32.const 1052140)
                 )
                 (unreachable)
                )
                (local.set $2
                 (i32.add
                  (local.get $2)
                  (i32.const 16)
                 )
                )
                (local.set $3
                 (block $block12 (result i32)
                  (if
                   (i64.ne
                    (i64.and
                     (i64.shr_s
                      (local.tee $10
                       (i64.rem_s
                        (local.get $8)
                        (local.get $9)
                       )
                      )
                      (i64.const 63)
                     )
                     (local.get $11)
                    )
                    (i64.sub
                     (i64.const 0)
                     (local.get $10)
                    )
                   )
                   (then
                    (br $block12
                     (call $_ZN6matrix7combine17h0b94f3addee26f52E
                      (local.get $9)
                      (local.get $2)
                      (i32.add
                       (local.get $6)
                       (i32.const 8)
                      )
                      (i64.sub
                       (i64.const 0)
                       (local.get $8)
                      )
                     )
                    )
                   )
                  )
                  (drop
                   (br_if $block12
                    (i32.const 0)
                    (i32.eqz
                     (local.tee $3
                      (i32.load
                       (local.get $2)
                      )
                     )
                    )
                   )
                  )
                  (i32.store
                   (local.get $3)
                   (local.tee $3
                    (i32.add
                     (i32.load
                      (local.get $3)
                     )
                     (i32.const 1)
                    )
                   )
                  )
                  (br_if $block4
                   (i32.eqz
                    (local.get $3)
                   )
                  )
                  (i32.load
                   (local.get $2)
                  )
                 )
                )
                (block $block13
                 (if
                  (local.tee $2
                   (call $dlmalloc
                    (i32.const 16)
                   )
                  )
                  (then
                   (i32.store offset=12
                    (local.get $2)
                    (local.get $5)
                   )
                   (i32.store offset=8
                    (local.get $2)
                    (local.get $3)
                   )
                   (i64.store align=4
                    (local.get $2)
                    (i64.const 4294967297)
                   )
                   (if
                    (i32.eqz
                     (local.tee $5
                      (i32.load offset=12
                       (local.get $4)
                      )
                     )
                    )
                    (then
                     (local.set $3
                      (i32.const 0)
                     )
                     (br $block13)
                    )
                   )
                   (i32.store
                    (local.get $5)
                    (local.tee $5
                     (i32.add
                      (i32.load
                       (local.get $5)
                      )
                      (i32.const 1)
                     )
                    )
                   )
                   (br_if $block4
                    (i32.eqz
                     (local.get $5)
                    )
                   )
                   (local.set $3
                    (i32.load offset=12
                     (local.get $4)
                    )
                   )
                   (br $block13)
                  )
                 )
                 (br $block14)
                )
                (i32.store
                 (local.get $6)
                 (local.get $3)
                )
                (i32.store
                 (local.get $4)
                 (local.tee $5
                  (i32.sub
                   (i32.load
                    (local.get $4)
                   )
                   (i32.const 1)
                  )
                 )
                )
                (if
                 (i32.eqz
                  (local.get $5)
                 )
                 (then
                  (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
                   (i32.add
                    (local.get $6)
                    (i32.const 12)
                   )
                  )
                 )
                )
                (local.set $5
                 (local.get $2)
                )
                (br_if $label
                 (local.tee $4
                  (local.get $3)
                 )
                )
               )
               (br $block8)
              )
              (call $_RNvNtCsdHhIpgkcIfN_4core9panicking18panic_bounds_check
               (local.get $3)
               (local.get $7)
               (i32.const 1052404)
              )
              (unreachable)
             )
             (i32.store
              (local.get $3)
              (local.tee $3
               (i32.add
                (i32.load
                 (local.get $3)
                )
                (i32.const 1)
               )
              )
             )
             (br_if $block4
              (i32.eqz
               (local.get $3)
              )
             )
             (i32.load offset=16
              (local.get $2)
             )
            )
           )
           (if
            (local.tee $2
             (call $dlmalloc
              (i32.const 16)
             )
            )
            (then
             (i32.store offset=12
              (local.get $2)
              (local.get $5)
             )
             (i32.store offset=8
              (local.get $2)
              (local.get $3)
             )
             (i64.store align=4
              (local.get $2)
              (i64.const 4294967297)
             )
             (i32.store
              (local.get $1)
              (local.tee $1
               (i32.sub
                (i32.load
                 (local.get $1)
                )
                (i32.const 1)
               )
              )
             )
             (if
              (i32.eqz
               (local.get $1)
              )
              (then
               (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
                (i32.add
                 (local.get $6)
                 (i32.const 4)
                )
               )
              )
             )
             (local.set $5
              (local.get $2)
             )
             (br_if $block15
              (i32.eqz
               (local.tee $1
                (local.get $4)
               )
              )
             )
             (br $label1)
            )
           )
          )
          (br $block14)
         )
        )
        (i32.store
         (local.get $1)
         (local.tee $0
          (i32.sub
           (i32.load
            (local.get $1)
           )
           (i32.const 1)
          )
         )
        )
        (br_if $block
         (local.get $0)
        )
        (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
         (local.get $6)
        )
        (br $block)
       )
       (block $block16
        (if
         (local.tee $5
          (call $dlmalloc
           (i32.const 24)
          )
         )
         (then
          (i32.store offset=16
           (local.get $5)
           (local.get $7)
          )
          (i64.store offset=8
           (local.get $5)
           (i64.const 1)
          )
          (i64.store
           (local.get $5)
           (i64.const 4294967297)
          )
          (i32.store offset=12
           (local.get $6)
           (local.tee $0
            (call $_ZN6matrix10row_reduce17hf3bb418bb445af8fE
             (local.get $0)
             (local.get $2)
            )
           )
          )
          (local.set $3
           (call $_ZN6matrix14prepend_column17had777f2f3eccd88bE
            (local.tee $2
             (i32.add
              (local.get $6)
              (i32.const 12)
             )
            )
           )
          )
          (br_if $block16
           (i32.eqz
            (local.tee $4
             (call $dlmalloc
              (i32.const 16)
             )
            )
           )
          )
          (i32.store offset=12
           (local.get $4)
           (local.get $3)
          )
          (i32.store offset=8
           (local.get $4)
           (local.get $5)
          )
          (i64.store align=4
           (local.get $4)
           (i64.const 4294967297)
          )
          (block $block17
           (br_if $block17
            (i32.eqz
             (local.get $0)
            )
           )
           (i32.store
            (local.get $0)
            (local.tee $0
             (i32.sub
              (i32.load
               (local.get $0)
              )
              (i32.const 1)
             )
            )
           )
           (br_if $block17
            (local.get $0)
           )
           (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
            (local.get $2)
           )
          )
          (i32.store
           (local.get $1)
           (local.tee $0
            (i32.sub
             (i32.load
              (local.get $1)
             )
             (i32.const 1)
            )
           )
          )
          (br_if $block
           (local.get $0)
          )
          (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
           (i32.add
            (local.get $6)
            (i32.const 4)
           )
          )
          (br $block)
         )
        )
        (call $_RNvNtCsi9YzqDQQz2q_5alloc5alloc18handle_alloc_error
         (i32.const 8)
         (i32.const 24)
        )
        (unreachable)
       )
       (br $block14)
      )
      (i32.store offset=12
       (local.get $6)
       (local.tee $0
        (call $_ZN6matrix10row_reduce17hf3bb418bb445af8fE
         (local.get $0)
         (local.get $5)
        )
       )
      )
      (local.set $4
       (call $_ZN6matrix14prepend_column17had777f2f3eccd88bE
        (local.tee $1
         (i32.add
          (local.get $6)
          (i32.const 12)
         )
        )
       )
      )
      (br_if $block
       (i32.eqz
        (local.get $0)
       )
      )
      (i32.store
       (local.get $0)
       (local.tee $0
        (i32.sub
         (i32.load
          (local.get $0)
         )
         (i32.const 1)
        )
       )
      )
      (br_if $block
       (local.get $0)
      )
      (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
       (local.get $1)
      )
     )
     (global.set $__stack_pointer
      (i32.add
       (local.get $6)
       (i32.const 16)
      )
     )
     (return
      (local.get $4)
     )
    )
    (if
     (local.tee $0
      (i32.load offset=12
       (local.get $1)
      )
     )
     (then
      (i32.store
       (local.get $0)
       (local.tee $0
        (i32.add
         (i32.load
          (local.get $0)
         )
         (i32.const 1)
        )
       )
      )
      (br_if $block4
       (i32.eqz
        (local.get $0)
       )
      )
     )
    )
    (call $_RNvNtNtCsdHhIpgkcIfN_4core9panicking11panic_const23panic_const_rem_by_zero
     (i32.const 1052420)
    )
    (unreachable)
   )
   (unreachable)
  )
  (call $_RNvNtCsi9YzqDQQz2q_5alloc5alloc18handle_alloc_error
   (i32.const 4)
   (i32.const 16)
  )
  (unreachable)
 )
