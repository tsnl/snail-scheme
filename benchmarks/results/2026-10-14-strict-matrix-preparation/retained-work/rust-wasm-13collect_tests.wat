(func $_ZN6matrix13collect_tests17hddfdb967308d3907E (param $0 i32) (param $1 i32) (param $2 i32) (param $3 i32) (param $4 i32) (param $5 i32) (param $6 i32)
  (local $7 i32)
  (local $8 i32)
  (local $9 i32)
  (local $10 i32)
  (local $11 i32)
  (global.set $__stack_pointer
   (local.tee $8
    (i32.sub
     (global.get $__stack_pointer)
     (i32.const 16)
    )
   )
  )
  (block $block3
   (block $block8
    (block $block9
     (if
      (i32.le_u
       (local.get $3)
       (local.get $4)
      )
      (then
       (block $block6
        (block $block5
         (block $block4
          (block $block
           (if
            (local.get $3)
            (then
             (local.set $9
              (i32.sub
               (local.get $3)
               (i32.const 1)
              )
             )
             (local.set $10
              (i32.add
               (local.get $8)
               (i32.const 12)
              )
             )
             (loop $label
              (br_if $block
               (i32.eq
                (local.get $3)
                (local.get $4)
               )
              )
              (local.set $11
               (block $block2 (result i32)
                (block $block1
                 (if
                  (local.tee $2
                   (i32.load
                    (local.get $2)
                   )
                  )
                  (then
                   (br_if $block1
                    (local.tee $7
                     (i32.load offset=8
                      (local.get $2)
                     )
                    )
                   )
                   (br $block2
                    (i32.const 0)
                   )
                  )
                 )
                 (call $_RNvNtCsdHhIpgkcIfN_4core6option13unwrap_failed
                  (i32.const 1052284)
                 )
                 (unreachable)
                )
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
                (br_if $block3
                 (i32.eqz
                  (local.get $7)
                 )
                )
                (i32.load offset=8
                 (local.get $2)
                )
               )
              )
              (if
               (i32.eq
                (local.tee $7
                 (i32.load offset=8
                  (local.get $5)
                 )
                )
                (i32.load
                 (local.get $5)
                )
               )
               (then
                (call $_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h1517403c739da271E
                 (local.get $5)
                )
               )
              )
              (i32.store offset=8
               (local.get $5)
               (i32.add
                (local.get $7)
                (i32.const 1)
               )
              )
              (i32.store
               (i32.add
                (i32.load offset=4
                 (local.get $5)
                )
                (i32.shl
                 (local.get $7)
                 (i32.const 2)
                )
               )
               (local.get $11)
              )
              (call $_ZN6matrix13collect_tests17hddfdb967308d3907E
               (local.get $0)
               (local.get $1)
               (local.tee $2
                (i32.add
                 (local.get $2)
                 (i32.const 12)
                )
               )
               (local.get $9)
               (local.tee $4
                (i32.sub
                 (local.get $4)
                 (i32.const 1)
                )
               )
               (local.get $5)
               (local.get $6)
              )
              (br_if $label
               (i32.eqz
                (local.tee $7
                 (i32.load offset=8
                  (local.get $5)
                 )
                )
               )
              )
              (i32.store offset=8
               (local.get $5)
               (local.tee $7
                (i32.sub
                 (local.get $7)
                 (i32.const 1)
                )
               )
              )
              (i32.store offset=8
               (local.get $8)
               (i32.const 1)
              )
              (i32.store offset=12
               (local.get $8)
               (local.tee $7
                (i32.load
                 (i32.add
                  (i32.load offset=4
                   (local.get $5)
                  )
                  (i32.shl
                   (local.get $7)
                   (i32.const 2)
                  )
                 )
                )
               )
              )
              (br_if $label
               (i32.eqz
                (local.get $7)
               )
              )
              (i32.store
               (local.get $7)
               (local.tee $7
                (i32.sub
                 (i32.load
                  (local.get $7)
                 )
                 (i32.const 1)
                )
               )
              )
              (br_if $label
               (local.get $7)
              )
              (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h68f3b70076e2971bE
               (local.get $10)
              )
              (br $label)
             )
             (unreachable)
            )
           )
           (br_if $block4
            (local.get $4)
           )
          )
          (br_if $block5
           (local.tee $2
            (i32.load
             (local.get $2)
            )
           )
          )
         )
         (local.set $2
          (i32.const 0)
         )
         (br $block6)
        )
        (i32.store
         (local.get $2)
         (local.tee $3
          (i32.add
           (i32.load
            (local.get $2)
           )
           (i32.const 1)
          )
         )
        )
        (br_if $block3
         (i32.eqz
          (local.get $3)
         )
        )
       )
       (block $block7
        (if
         (i32.eqz
          (local.tee $3
           (i32.load offset=8
            (local.get $5)
           )
          )
         )
         (then
          (local.set $5
           (local.get $2)
          )
          (br $block7)
         )
        )
        (local.set $7
         (i32.sub
          (i32.load offset=4
           (local.get $5)
          )
          (i32.const 4)
         )
        )
        (local.set $4
         (i32.shl
          (local.get $3)
          (i32.const 2)
         )
        )
        (loop $label1
         (if
          (local.tee $3
           (i32.load
            (i32.add
             (local.get $4)
             (local.get $7)
            )
           )
          )
          (then
           (i32.store
            (local.get $3)
            (local.tee $5
             (i32.add
              (i32.load
               (local.get $3)
              )
              (i32.const 1)
             )
            )
           )
           (br_if $block3
            (i32.eqz
             (local.get $5)
            )
           )
          )
         )
         (br_if $block8
          (i32.eqz
           (local.tee $5
            (call $dlmalloc
             (i32.const 16)
            )
           )
          )
         )
         (i32.store offset=12
          (local.get $5)
          (local.get $2)
         )
         (i32.store offset=8
          (local.get $5)
          (local.get $3)
         )
         (i64.store align=4
          (local.get $5)
          (i64.const 4294967297)
         )
         (local.set $2
          (local.get $5)
         )
         (br_if $label1
          (local.tee $4
           (i32.sub
            (local.get $4)
            (i32.const 4)
           )
          )
         )
        )
       )
       (if
        (local.tee $2
         (i32.load
          (local.get $1)
         )
        )
        (then
         (i32.store
          (local.get $2)
          (local.tee $1
           (i32.add
            (i32.load
             (local.get $2)
            )
            (i32.const 1)
           )
          )
         )
         (br_if $block3
          (i32.eqz
           (local.get $1)
          )
         )
        )
       )
       (br_if $block9
        (i32.eqz
         (local.tee $1
          (call $dlmalloc
           (i32.const 16)
          )
         )
        )
       )
       (i32.store offset=12
        (local.get $1)
        (local.get $5)
       )
       (i32.store offset=8
        (local.get $1)
        (local.get $2)
       )
       (i64.store align=4
        (local.get $1)
        (i64.const 4294967297)
       )
       (local.set $4
        (call $_ZN6matrix10row_reduce17hf3bb418bb445af8fE
         (local.get $0)
         (local.get $1)
        )
       )
       (if
        (i32.eq
         (local.tee $5
          (i32.load offset=12
           (local.get $6)
          )
         )
         (local.tee $2
          (local.tee $0
           (i32.load
            (local.get $6)
           )
          )
         )
        )
        (then
         (call $_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17h1517403c739da271E
          (local.get $6)
         )
         (block $block10
          (br_if $block10
           (i32.le_u
            (local.tee $2
             (i32.load offset=8
              (local.get $6)
             )
            )
            (i32.sub
             (local.get $0)
             (local.tee $3
              (i32.load offset=12
               (local.get $6)
              )
             )
            )
           )
          )
          (if
           (i32.eqz
            (i32.and
             (i32.gt_u
              (local.tee $1
               (i32.sub
                (local.get $0)
                (local.get $2)
               )
              )
              (local.tee $3
               (i32.sub
                (local.get $3)
                (local.get $1)
               )
              )
             )
             (i32.ge_u
              (i32.sub
               (local.tee $5
                (i32.load
                 (local.get $6)
                )
               )
               (local.get $0)
              )
              (local.get $3)
             )
            )
           )
           (then
            (local.set $0
             (i32.sub
              (local.get $5)
              (local.get $1)
             )
            )
            (if
             (local.tee $1
              (i32.shl
               (local.get $1)
               (i32.const 2)
              )
             )
             (then
              (memory.copy
               (i32.add
                (local.tee $3
                 (i32.load offset=4
                  (local.get $6)
                 )
                )
                (i32.shl
                 (local.get $0)
                 (i32.const 2)
                )
               )
               (i32.add
                (local.get $3)
                (i32.shl
                 (local.get $2)
                 (i32.const 2)
                )
               )
               (local.get $1)
              )
             )
            )
            (i32.store offset=8
             (local.get $6)
             (local.get $0)
            )
            (br $block10)
           )
          )
          (br_if $block10
           (i32.eqz
            (local.tee $1
             (i32.shl
              (local.get $3)
              (i32.const 2)
             )
            )
           )
          )
          (memory.copy
           (i32.add
            (local.tee $2
             (i32.load offset=4
              (local.get $6)
             )
            )
            (i32.shl
             (local.get $0)
             (i32.const 2)
            )
           )
           (local.get $2)
           (local.get $1)
          )
         )
         (local.set $5
          (i32.load offset=12
           (local.get $6)
          )
         )
         (local.set $2
          (i32.load
           (local.get $6)
          )
         )
        )
       )
       (i32.store offset=12
        (local.get $6)
        (i32.add
         (local.get $5)
         (i32.const 1)
        )
       )
       (i32.store offset=8
        (local.get $6)
        (local.tee $0
         (select
          (local.tee $1
           (i32.add
            (local.tee $0
             (i32.sub
              (i32.load offset=8
               (local.get $6)
              )
              (i32.const 1)
             )
            )
            (local.get $2)
           )
          )
          (local.get $0)
          (i32.gt_u
           (local.get $0)
           (local.get $1)
          )
         )
        )
       )
       (i32.store
        (i32.add
         (i32.load offset=4
          (local.get $6)
         )
         (i32.shl
          (local.get $0)
          (i32.const 2)
         )
        )
        (local.get $4)
       )
      )
     )
     (global.set $__stack_pointer
      (i32.add
       (local.get $8)
       (i32.const 16)
      )
     )
     (return)
    )
    (call $_RNvNtCsi9YzqDQQz2q_5alloc5alloc18handle_alloc_error
     (i32.const 4)
     (i32.const 16)
    )
    (unreachable)
   )
   (call $_RNvNtCsi9YzqDQQz2q_5alloc5alloc18handle_alloc_error
    (i32.const 4)
    (i32.const 16)
   )
   (unreachable)
  )
  (unreachable)
 )
