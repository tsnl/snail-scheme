(func $_ZN6matrix6search17hc9885ee55d90aef9E (param $0 i32) (param $1 i32) (param $2 i32) (param $3 i32) (param $4 i32) (param $5 i32)
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
  (local $25 i64)
  (local $26 i64)
  (local $scratch i32)
  (global.set $__stack_pointer
   (local.tee $8
    (i32.sub
     (global.get $__stack_pointer)
     (i32.const 80)
    )
   )
  )
  (i32.store offset=16
   (local.get $8)
   (local.get $4)
  )
  (i32.store offset=12
   (local.get $8)
   (local.get $3)
  )
  (block $block11
   (block $block2
    (local.set $13
     (block $block1 (result i32)
      (if
       (i32.le_u
        (local.get $1)
        (local.get $2)
       )
       (then
        (i64.store offset=32 align=4
         (local.get $8)
         (i64.const 17179869184)
        )
        (i64.store offset=40 align=4
         (local.get $8)
         (i64.const 0)
        )
        (if
         (local.tee $9
          (i32.load offset=12
           (local.get $3)
          )
         )
         (then
          (loop $label
           (local.set $6
            (i32.add
             (local.get $6)
             (i32.const 1)
            )
           )
           (br_if $label
            (local.tee $9
             (i32.load offset=12
              (local.get $9)
             )
            )
           )
          )
         )
        )
        (i32.store offset=76
         (local.get $8)
         (i32.const 0)
        )
        (i64.store offset=68 align=4
         (local.get $8)
         (i64.const 17179869184)
        )
        (call $_ZN6matrix13collect_tests17hddfdb967308d3907E
         (local.get $0)
         (i32.add
          (local.get $3)
          (i32.const 8)
         )
         (i32.add
          (local.get $3)
          (i32.const 12)
         )
         (i32.sub
          (local.get $1)
          (i32.const 2)
         )
         (local.get $6)
         (i32.add
          (local.get $8)
          (i32.const 68)
         )
         (i32.add
          (local.get $8)
          (i32.const 32)
         )
        )
        (local.set $7
         (i32.load offset=72
          (local.get $8)
         )
        )
        (if
         (local.tee $10
          (i32.load offset=76
           (local.get $8)
          )
         )
         (then
          (local.set $6
           (local.get $7)
          )
          (loop $label1
           (block $block
            (br_if $block
             (i32.eqz
              (local.tee $9
               (i32.load
                (local.get $6)
               )
              )
             )
            )
            (i32.store
             (local.get $9)
             (local.tee $9
              (i32.sub
               (i32.load
                (local.get $9)
               )
               (i32.const 1)
              )
             )
            )
            (br_if $block
             (local.get $9)
            )
            (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h68f3b70076e2971bE
             (local.get $6)
            )
           )
           (local.set $6
            (i32.add
             (local.get $6)
             (i32.const 4)
            )
           )
           (br_if $label1
            (local.tee $10
             (i32.sub
              (local.get $10)
              (i32.const 1)
             )
            )
           )
          )
         )
        )
        (if
         (i32.load offset=68
          (local.get $8)
         )
         (then
          (call $dlfree
           (local.get $7)
          )
         )
        )
        (local.set $16
         (i32.load offset=44
          (local.get $8)
         )
        )
        (local.set $18
         (i32.load offset=40
          (local.get $8)
         )
        )
        (local.set $14
         (i32.load offset=32
          (local.get $8)
         )
        )
        (br $block1
         (i32.load offset=36
          (local.get $8)
         )
        )
       )
      )
      (i32.store
       (local.get $3)
       (local.tee $6
        (i32.add
         (i32.load
          (local.get $3)
         )
         (i32.const 1)
        )
       )
      )
      (br_if $block2
       (i32.eqz
        (local.get $6)
       )
      )
      (local.set $14
       (i32.const -2147483648)
      )
      (call $_ZN6matrix10row_reduce17hf3bb418bb445af8fE
       (local.get $0)
       (local.get $3)
      )
     )
    )
    (local.set $25
     (i64.load
      (local.get $0)
     )
    )
    (i32.store offset=32
     (local.get $8)
     (i32.const 0)
    )
    (block $block3
     (br_if $block3
      (i32.eqz
       (local.get $4)
      )
     )
     (block $block12
      (if
       (i32.ne
        (local.get $14)
        (i32.const -2147483648)
       )
       (then
        (local.set $10
         (i32.add
          (local.get $13)
          (local.tee $23
           (select
            (i32.shl
             (i32.sub
              (local.get $16)
              (local.tee $6
               (i32.sub
                (local.get $14)
                (local.tee $20
                 (i32.sub
                  (local.get $18)
                  (select
                   (local.get $14)
                   (i32.const 0)
                   (i32.le_u
                    (local.get $14)
                    (local.get $18)
                   )
                  )
                 )
                )
               )
              )
             )
             (i32.const 2)
            )
            (i32.const 0)
            (local.tee $6
             (i32.lt_u
              (local.get $6)
              (local.get $16)
             )
            )
           )
          )
         )
        )
        (local.set $21
         (i32.add
          (local.get $13)
          (i32.shl
           (local.tee $24
            (select
             (local.get $14)
             (i32.add
              (local.get $16)
              (local.get $20)
             )
             (local.get $6)
            )
           )
           (i32.const 2)
          )
         )
        )
        (local.set $11
         (i32.add
          (local.get $13)
          (i32.shl
           (local.get $20)
           (i32.const 2)
          )
         )
        )
        (local.set $15
         (local.get $4)
        )
        (loop $label4
         (local.set $6
          (i32.load offset=8
           (local.get $15)
          )
         )
         (block $block7
          (local.set $7
           (block $block10 (result i32)
            (block $block9
             (block $block6
              (block $block5
               (block $block4
                (if
                 (local.get $16)
                 (then
                  (local.set $17
                   (local.get $10)
                  )
                  (local.set $7
                   (local.get $21)
                  )
                  (local.set $9
                   (local.get $11)
                  )
                  (br_if $block4
                   (i32.eqz
                    (local.get $6)
                   )
                  )
                  (br $block5)
                 )
                )
                (local.set $9
                 (local.tee $7
                  (local.tee $17
                   (local.get $13)
                  )
                 )
                )
                (br_if $block5
                 (local.get $6)
                )
                (br $block6)
               )
               (if
                (i32.ne
                 (local.get $20)
                 (local.get $24)
                )
                (then
                 (br_if $block7
                  (i32.eqz
                   (local.tee $6
                    (i32.load
                     (local.get $11)
                    )
                   )
                  )
                 )
                 (br_if $block2
                  (i32.eq
                   (i32.load
                    (local.get $6)
                   )
                   (i32.const -1)
                  )
                 )
                 (br $block7)
                )
               )
               (br_if $block6
                (i32.eqz
                 (local.get $23)
                )
               )
               (br_if $block7
                (i32.eqz
                 (local.tee $6
                  (i32.load
                   (local.get $13)
                  )
                 )
                )
               )
               (br_if $block7
                (i32.ne
                 (i32.load
                  (local.get $6)
                 )
                 (i32.const -1)
                )
               )
               (unreachable)
              )
              (loop $label3
               (block $block8
                (if
                 (i32.eq
                  (local.get $7)
                  (local.get $9)
                 )
                 (then
                  (local.set $9
                   (local.get $13)
                  )
                  (loop $label2
                   (br_if $block8
                    (i32.eq
                     (local.get $9)
                     (local.get $17)
                    )
                   )
                   (if
                    (local.tee $7
                     (i32.load
                      (local.get $9)
                     )
                    )
                    (then
                     (i32.store
                      (local.get $7)
                      (local.tee $19
                       (i32.add
                        (i32.load
                         (local.get $7)
                        )
                        (i32.const 1)
                       )
                      )
                     )
                     (br_if $block2
                      (i32.eqz
                       (local.get $19)
                      )
                     )
                    )
                   )
                   (i32.store
                    (local.get $6)
                    (local.tee $19
                     (i32.add
                      (i32.load
                       (local.get $6)
                      )
                      (i32.const 1)
                     )
                    )
                   )
                   (br_if $block2
                    (i32.eqz
                     (local.get $19)
                    )
                   )
                   (local.set $9
                    (i32.add
                     (local.get $9)
                     (i32.const 4)
                    )
                   )
                   (br_if $label2
                    (i32.eqz
                     (call $_ZN6matrix12in_row_space17h3bc986fb2a06e8e3E
                      (local.get $25)
                      (local.get $7)
                      (local.get $6)
                     )
                    )
                   )
                  )
                  (br $block7)
                 )
                )
                (if
                 (local.tee $19
                  (i32.load
                   (local.get $9)
                  )
                 )
                 (then
                  (i32.store
                   (local.get $19)
                   (local.tee $22
                    (i32.add
                     (i32.load
                      (local.get $19)
                     )
                     (i32.const 1)
                    )
                   )
                  )
                  (br_if $block2
                   (i32.eqz
                    (local.get $22)
                   )
                  )
                 )
                )
                (i32.store
                 (local.get $6)
                 (local.tee $22
                  (i32.add
                   (i32.load
                    (local.get $6)
                   )
                   (i32.const 1)
                  )
                 )
                )
                (br_if $block2
                 (i32.eqz
                  (local.get $22)
                 )
                )
                (local.set $9
                 (i32.add
                  (local.get $9)
                  (i32.const 4)
                 )
                )
                (br_if $label3
                 (i32.eqz
                  (call $_ZN6matrix12in_row_space17h3bc986fb2a06e8e3E
                   (local.get $25)
                   (local.get $19)
                   (local.get $6)
                  )
                 )
                )
                (br $block7)
               )
              )
              (br_if $block9
               (local.tee $6
                (i32.load offset=8
                 (local.get $15)
                )
               )
              )
             )
             (br $block10
              (i32.const 0)
             )
            )
            (i32.store
             (local.get $6)
             (local.tee $6
              (i32.add
               (i32.load
                (local.get $6)
               )
               (i32.const 1)
              )
             )
            )
            (br_if $block2
             (i32.eqz
              (local.get $6)
             )
            )
            (i32.load offset=8
             (local.get $15)
            )
           )
          )
          (br_if $block11
           (i32.eqz
            (local.tee $6
             (call $dlmalloc
              (i32.const 16)
             )
            )
           )
          )
          (i32.store offset=12
           (local.get $6)
           (local.get $12)
          )
          (i32.store offset=8
           (local.get $6)
           (local.get $7)
          )
          (i64.store align=4
           (local.get $6)
           (i64.const 4294967297)
          )
          (i32.store offset=32
           (local.get $8)
           (local.get $6)
          )
          (local.set $12
           (local.get $6)
          )
         )
         (br_if $label4
          (local.tee $15
           (i32.load offset=12
            (local.get $15)
           )
          )
         )
        )
        (br $block12)
       )
      )
      (if
       (local.get $13)
       (then
        (local.set $9
         (local.get $4)
        )
        (loop $label5
         (local.set $6
          (i32.load offset=8
           (local.get $9)
          )
         )
         (i32.store
          (local.get $13)
          (local.tee $11
           (i32.add
            (local.tee $7
             (i32.load
              (local.get $13)
             )
            )
            (i32.const 1)
           )
          )
         )
         (br_if $block2
          (i32.eqz
           (local.get $11)
          )
         )
         (block $block13
          (if
           (i32.eqz
            (local.get $6)
           )
           (then
            (i32.store
             (local.get $13)
             (local.get $7)
            )
            (br $block13)
           )
          )
          (i32.store
           (local.get $6)
           (local.tee $7
            (i32.add
             (i32.load
              (local.get $6)
             )
             (i32.const 1)
            )
           )
          )
          (br_if $block2
           (i32.eqz
            (local.get $7)
           )
          )
          (br_if $block13
           (call $_ZN6matrix12in_row_space17h3bc986fb2a06e8e3E
            (local.get $25)
            (local.get $13)
            (local.get $6)
           )
          )
          (local.set $7
           (if (result i32)
            (local.tee $6
             (i32.load offset=8
              (local.get $9)
             )
            )
            (then
             (i32.store
              (local.get $6)
              (local.tee $6
               (i32.add
                (i32.load
                 (local.get $6)
                )
                (i32.const 1)
               )
              )
             )
             (br_if $block2
              (i32.eqz
               (local.get $6)
              )
             )
             (i32.load offset=8
              (local.get $9)
             )
            )
            (else
             (i32.const 0)
            )
           )
          )
          (br_if $block11
           (i32.eqz
            (local.tee $6
             (call $dlmalloc
              (i32.const 16)
             )
            )
           )
          )
          (i32.store offset=12
           (local.get $6)
           (local.get $12)
          )
          (i32.store offset=8
           (local.get $6)
           (local.get $7)
          )
          (i64.store align=4
           (local.get $6)
           (i64.const 4294967297)
          )
          (i32.store offset=32
           (local.get $8)
           (local.get $6)
          )
          (local.set $12
           (local.get $6)
          )
         )
         (br_if $label5
          (local.tee $9
           (i32.load offset=12
            (local.get $9)
           )
          )
         )
        )
        (br $block12)
       )
      )
      (local.set $6
       (local.get $4)
      )
      (loop $label6
       (block $block14
        (br_if $block14
         (i32.eqz
          (local.tee $7
           (i32.load offset=8
            (local.get $6)
           )
          )
         )
        )
        (i32.store
         (local.get $7)
         (local.tee $9
          (i32.add
           (i32.load
            (local.get $7)
           )
           (i32.const 1)
          )
         )
        )
        (br_if $block2
         (i32.eqz
          (local.get $9)
         )
        )
        (br_if $block14
         (call $_ZN6matrix12in_row_space17h3bc986fb2a06e8e3E
          (local.get $25)
          (i32.const 0)
          (local.get $7)
         )
        )
        (local.set $9
         (if (result i32)
          (local.tee $7
           (i32.load offset=8
            (local.get $6)
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
           (br_if $block2
            (i32.eqz
             (local.get $7)
            )
           )
           (i32.load offset=8
            (local.get $6)
           )
          )
          (else
           (i32.const 0)
          )
         )
        )
        (br_if $block11
         (i32.eqz
          (local.tee $7
           (call $dlmalloc
            (i32.const 16)
           )
          )
         )
        )
        (i32.store offset=12
         (local.get $7)
         (local.get $12)
        )
        (i32.store offset=8
         (local.get $7)
         (local.get $9)
        )
        (i64.store align=4
         (local.get $7)
         (i64.const 4294967297)
        )
        (i32.store offset=32
         (local.get $8)
         (local.get $7)
        )
        (local.set $12
         (local.get $7)
        )
       )
       (br_if $label6
        (local.tee $6
         (i32.load offset=12
          (local.get $6)
         )
        )
       )
      )
     )
     (if
      (i32.eqz
       (local.get $12)
      )
      (then
       (local.set $11
        (i32.const 0)
       )
       (br $block3)
      )
     )
     (local.set $7
      (i32.const 0)
     )
     (local.set $6
      (local.get $12)
     )
     (loop $label7
      (local.set $9
       (i32.const 0)
      )
      (if
       (local.tee $11
        (i32.load offset=8
         (local.get $6)
        )
       )
       (then
        (i32.store
         (local.get $11)
         (local.tee $9
          (i32.add
           (i32.load
            (local.get $11)
           )
           (i32.const 1)
          )
         )
        )
        (br_if $block2
         (i32.eqz
          (local.get $9)
         )
        )
        (local.set $9
         (i32.load offset=8
          (local.get $6)
         )
        )
       )
      )
      (br_if $block11
       (i32.eqz
        (local.tee $11
         (call $dlmalloc
          (i32.const 16)
         )
        )
       )
      )
      (i32.store offset=12
       (local.get $11)
       (local.get $7)
      )
      (i32.store offset=8
       (local.get $11)
       (local.get $9)
      )
      (i64.store align=4
       (local.get $11)
       (i64.const 4294967297)
      )
      (local.set $7
       (local.get $11)
      )
      (br_if $label7
       (local.tee $6
        (i32.load offset=12
         (local.get $6)
        )
       )
      )
     )
     (i32.store
      (local.get $12)
      (local.tee $6
       (i32.sub
        (i32.load
         (local.get $12)
        )
        (i32.const 1)
       )
      )
     )
     (br_if $block3
      (local.get $6)
     )
     (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
      (i32.add
       (local.get $8)
       (i32.const 32)
      )
     )
    )
    (i32.store offset=44
     (local.get $8)
     (local.get $16)
    )
    (i32.store offset=40
     (local.get $8)
     (local.get $18)
    )
    (i32.store offset=36
     (local.get $8)
     (local.get $13)
    )
    (i32.store offset=32
     (local.get $8)
     (local.get $14)
    )
    (block $block15
     (if
      (i32.eq
       (local.get $14)
       (i32.const -2147483648)
      )
      (then
       (br_if $block15
        (i32.eqz
         (local.get $13)
        )
       )
       (i32.store
        (local.get $13)
        (local.tee $6
         (i32.sub
          (i32.load
           (local.get $13)
          )
          (i32.const 1)
         )
        )
       )
       (br_if $block15
        (local.get $6)
       )
       (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
        (i32.add
         (local.get $8)
         (i32.const 36)
        )
       )
       (br $block15)
      )
     )
     (block $block16
      (br_if $block16
       (i32.eqz
        (local.get $16)
       )
      )
      (if
       (i32.ne
        (local.tee $12
         (select
          (local.get $14)
          (i32.add
           (local.tee $6
            (i32.sub
             (local.get $18)
             (select
              (local.get $14)
              (i32.const 0)
              (i32.le_u
               (local.get $14)
               (local.get $18)
              )
             )
            )
           )
           (local.get $16)
          )
          (i32.gt_u
           (local.get $16)
           (local.tee $7
            (i32.sub
             (local.get $14)
             (local.get $6)
            )
           )
          )
         )
        )
        (local.get $6)
       )
       (then
        (local.set $10
         (i32.sub
          (local.get $12)
          (local.get $6)
         )
        )
        (local.set $6
         (i32.add
          (local.get $13)
          (i32.shl
           (local.get $6)
           (i32.const 2)
          )
         )
        )
        (loop $label8
         (block $block17
          (br_if $block17
           (i32.eqz
            (local.tee $12
             (i32.load
              (local.get $6)
             )
            )
           )
          )
          (i32.store
           (local.get $12)
           (local.tee $12
            (i32.sub
             (i32.load
              (local.get $12)
             )
             (i32.const 1)
            )
           )
          )
          (br_if $block17
           (local.get $12)
          )
          (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
           (local.get $6)
          )
         )
         (local.set $6
          (i32.add
           (local.get $6)
           (i32.const 4)
          )
         )
         (br_if $label8
          (local.tee $10
           (i32.sub
            (local.get $10)
            (i32.const 1)
           )
          )
         )
        )
       )
      )
      (br_if $block16
       (i32.ge_u
        (local.get $7)
        (local.get $16)
       )
      )
      (local.set $10
       (select
        (local.tee $6
         (i32.sub
          (local.get $16)
          (local.get $7)
         )
        )
        (i32.const 0)
        (i32.le_u
         (local.get $6)
         (local.get $16)
        )
       )
      )
      (local.set $6
       (local.get $13)
      )
      (loop $label9
       (block $block18
        (br_if $block18
         (i32.eqz
          (local.tee $7
           (i32.load
            (local.get $6)
           )
          )
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
        (br_if $block18
         (local.get $7)
        )
        (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
         (local.get $6)
        )
       )
       (local.set $6
        (i32.add
         (local.get $6)
         (i32.const 4)
        )
       )
       (br_if $label9
        (local.tee $10
         (i32.sub
          (local.get $10)
          (i32.const 1)
         )
        )
       )
      )
     )
     (br_if $block15
      (i32.eqz
       (local.get $14)
      )
     )
     (call $dlfree
      (local.get $13)
     )
    )
    (block $block21
     (block $block19
      (block $block22
       (if
        (i32.eqz
         (local.get $11)
        )
        (then
         (local.set $11
          (i32.const 0)
         )
         (local.set $9
          (local.get $3)
         )
         (loop $label10
          (local.set $10
           (i32.const 0)
          )
          (if
           (local.tee $0
            (i32.load offset=8
             (local.get $9)
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
            (br_if $block2
             (i32.eqz
              (local.get $0)
             )
            )
            (local.set $10
             (i32.load offset=8
              (local.get $9)
             )
            )
           )
          )
          (br_if $block11
           (i32.eqz
            (local.tee $0
             (call $dlmalloc
              (i32.const 16)
             )
            )
           )
          )
          (i32.store offset=12
           (local.get $0)
           (local.get $11)
          )
          (i32.store offset=8
           (local.get $0)
           (local.get $10)
          )
          (i64.store align=4
           (local.get $0)
           (i64.const 4294967297)
          )
          (local.set $11
           (local.get $0)
          )
          (br_if $label10
           (local.tee $9
            (i32.load offset=12
             (local.get $9)
            )
           )
          )
         )
         (i32.store offset=32
          (local.get $8)
          (local.get $11)
         )
         (local.set $9
          (i32.const 0)
         )
         (local.set $10
          (local.get $11)
         )
         (loop $label11
          (local.set $9
           (i32.add
            (local.get $9)
            (i32.const 1)
           )
          )
          (br_if $label11
           (local.tee $10
            (i32.load offset=12
             (local.get $10)
            )
           )
          )
         )
         (br_if $block19
          (i64.gt_s
           (local.tee $26
            (i64.load offset=16
             (local.get $5)
            )
           )
           (local.tee $25
            (i64.extend_i32_u
             (local.get $9)
            )
           )
          )
         )
         (block $block20
          (if
           (i64.le_s
            (local.get $25)
            (local.get $26)
           )
           (then
            (i32.store offset=24
             (local.get $5)
             (local.tee $1
              (i32.add
               (i32.load offset=24
                (local.get $5)
               )
               (i32.const 1)
              )
             )
            )
            (br_if $block20
             (i32.ge_u
              (local.get $1)
              (i32.const 3000)
             )
            )
            (i32.store offset=12
             (local.get $5)
             (i32.add
              (if (result i32)
               (i32.eq
                (local.tee $1
                 (i32.load offset=12
                  (local.get $5)
                 )
                )
                (local.tee $10
                 (i32.load
                  (local.get $5)
                 )
                )
               )
               (then
                (call $_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$4grow17hf5b232e619a17465E
                 (local.get $5)
                )
                (local.set $10
                 (i32.load
                  (local.get $5)
                 )
                )
                (i32.load offset=12
                 (local.get $5)
                )
               )
               (else
                (local.get $1)
               )
              )
              (i32.const 1)
             )
            )
            (i32.store offset=8
             (local.get $5)
             (local.tee $1
              (select
               (local.tee $2
                (i32.add
                 (local.tee $1
                  (i32.sub
                   (i32.load offset=8
                    (local.get $5)
                   )
                   (i32.const 1)
                  )
                 )
                 (local.get $10)
                )
               )
               (local.get $1)
               (i32.gt_u
                (local.get $1)
                (local.get $2)
               )
              )
             )
            )
            (i32.store offset=4
             (local.tee $1
              (i32.add
               (i32.load offset=4
                (local.get $5)
               )
               (i32.shl
                (local.get $1)
                (i32.const 3)
               )
              )
             )
             (local.get $0)
            )
            (i32.store
             (local.get $1)
             (i32.const 0)
            )
            (br $block21)
           )
          )
          (i32.store offset=24
           (local.get $5)
           (i32.const 1)
          )
          (i64.store offset=16
           (local.get $5)
           (local.get $25)
          )
          (br_if $block22
           (i32.eqz
            (local.tee $1
             (call $dlmalloc
              (i32.const 8)
             )
            )
           )
          )
          (i32.store offset=4
           (local.get $1)
           (local.get $0)
          )
          (i32.store
           (local.get $1)
           (i32.const 0)
          )
          (call $_ZN4core3ptr82drop_in_place$LT$alloc..collections..vec_deque..VecDeque$LT$matrix..Answer$GT$$GT$17h269ab4c7de1129cfE
           (local.get $5)
          )
          (i64.store offset=8
           (local.get $5)
           (i64.const 4294967296)
          )
          (i32.store offset=4
           (local.get $5)
           (local.get $1)
          )
          (i32.store
           (local.get $5)
           (i32.const 1)
          )
          (br $block21)
         )
         (block $block23
          (if
           (i32.ne
            (local.get $1)
            (i32.const 3000)
           )
           (then
            (i32.store
             (local.get $0)
             (i32.const 0)
            )
            (br $block23)
           )
          )
          (if
           (i32.eq
            (local.tee $10
             (i32.load offset=12
              (local.get $5)
             )
            )
            (local.tee $11
             (i32.load
              (local.get $5)
             )
            )
           )
           (then
            (call $_ZN5alloc11collections9vec_deque21VecDeque$LT$T$C$A$GT$4grow17hf5b232e619a17465E
             (local.get $5)
            )
            (local.set $10
             (i32.load offset=12
              (local.get $5)
             )
            )
            (local.set $11
             (i32.load
              (local.get $5)
             )
            )
           )
          )
          (i32.store
           (i32.add
            (i32.load offset=4
             (local.get $5)
            )
            (i32.shl
             (local.tee $1
              (select
               (local.tee $2
                (i32.add
                 (local.tee $1
                  (i32.sub
                   (i32.load offset=8
                    (local.get $5)
                   )
                   (i32.const 1)
                  )
                 )
                 (local.get $11)
                )
               )
               (local.get $1)
               (i32.gt_u
                (local.get $1)
                (local.get $2)
               )
              )
             )
             (i32.const 3)
            )
           )
           (i32.const 1)
          )
          (i32.store offset=12
           (local.get $5)
           (i32.add
            (local.get $10)
            (i32.const 1)
           )
          )
          (i32.store offset=8
           (local.get $5)
           (local.get $1)
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
          (br_if $block21
           (local.get $0)
          )
         )
         (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
          (i32.add
           (local.get $8)
           (i32.const 32)
          )
         )
         (br $block21)
        )
       )
       (local.set $21
        (i32.add
         (local.get $2)
         (i32.const 1)
        )
       )
       (local.set $16
        (i32.add
         (local.get $8)
         (i32.const 52)
        )
       )
       (loop $label18
        (i32.store offset=20
         (local.get $8)
         (local.get $11)
        )
        (local.set $6
         (i32.const 0)
        )
        (if
         (local.tee $2
          (i32.load offset=8
           (local.get $11)
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
          (br_if $block2
           (i32.eqz
            (local.get $2)
           )
          )
          (local.set $6
           (i32.load offset=8
            (local.get $11)
           )
          )
         )
        )
        (i32.store
         (local.get $3)
         (local.tee $2
          (i32.add
           (i32.load
            (local.get $3)
           )
           (i32.const 1)
          )
         )
        )
        (br_if $block2
         (i32.eqz
          (local.get $2)
         )
        )
        (block $block33
         (if
          (local.tee $2
           (call $dlmalloc
            (i32.const 16)
           )
          )
          (then
           (i32.store offset=12
            (local.get $2)
            (local.get $3)
           )
           (i32.store offset=8
            (local.get $2)
            (local.get $6)
           )
           (i64.store align=4
            (local.get $2)
            (i64.const 4294967297)
           )
           (i32.store offset=24
            (local.get $8)
            (local.get $2)
           )
           (local.set $7
            (i32.const 0)
           )
           (local.set $6
            (local.get $2)
           )
           (block $block24
            (loop $label12
             (local.set $10
              (i32.const 0)
             )
             (if
              (local.tee $12
               (i32.load offset=8
                (local.get $6)
               )
              )
              (then
               (i32.store
                (local.get $12)
                (local.tee $12
                 (i32.add
                  (i32.load
                   (local.get $12)
                  )
                  (i32.const 1)
                 )
                )
               )
               (br_if $block2
                (i32.eqz
                 (local.get $12)
                )
               )
               (local.set $10
                (i32.load offset=8
                 (local.get $6)
                )
               )
              )
             )
             (br_if $block24
              (i32.eqz
               (local.tee $9
                (call $dlmalloc
                 (i32.const 16)
                )
               )
              )
             )
             (i32.store offset=12
              (local.get $9)
              (local.get $7)
             )
             (i32.store offset=8
              (local.get $9)
              (local.get $10)
             )
             (i64.store align=4
              (local.get $9)
              (i64.const 4294967297)
             )
             (local.set $7
              (local.get $9)
             )
             (br_if $label12
              (local.tee $6
               (i32.load offset=12
                (local.get $6)
               )
              )
             )
            )
            (i32.store offset=28
             (local.get $8)
             (local.get $7)
            )
            (i32.store
             (local.get $7)
             (i32.const 2)
            )
            (local.set $12
             (i32.const 0)
            )
            (i32.store offset=40
             (local.get $8)
             (i32.const 0)
            )
            (i32.store offset=36
             (local.get $8)
             (local.get $7)
            )
            (i32.store offset=32
             (local.get $8)
             (i32.const 1)
            )
            (i32.store offset=52
             (local.get $8)
             (i32.const 0)
            )
            (i32.store offset=48
             (local.get $8)
             (local.get $7)
            )
            (local.set $18
             (i32.add
              (local.get $7)
              (i32.const 12)
             )
            )
            (local.set $15
             (local.get $7)
            )
            (block $block30
             (block $block35
              (loop $label17
               (local.set $7
                (i32.const 0)
               )
               (if
                (local.tee $6
                 (i32.load offset=8
                  (local.get $15)
                 )
                )
                (then
                 (loop $label13
                  (local.set $7
                   (i32.add
                    (local.get $7)
                    (i32.const 1)
                   )
                  )
                  (br_if $label13
                   (local.tee $6
                    (i32.load offset=16
                     (local.get $6)
                    )
                   )
                  )
                 )
                )
               )
               (i32.store offset=56
                (local.get $8)
                (block $block27 (result i32)
                 (block $block26
                  (block $block25
                   (if
                    (local.tee $6
                     (i32.load offset=12
                      (local.get $15)
                     )
                    )
                    (then
                     (i32.store
                      (local.get $6)
                      (local.tee $6
                       (i32.add
                        (i32.load
                         (local.get $6)
                        )
                        (i32.const 1)
                       )
                      )
                     )
                     (br_if $block2
                      (i32.eqz
                       (local.get $6)
                      )
                     )
                     (local.set $6
                      (i32.load offset=12
                       (local.get $15)
                      )
                     )
                     (br_if $block25
                      (local.get $12)
                     )
                     (br $block26)
                    )
                   )
                   (drop
                    (br_if $block27
                     (local.tee $6
                      (i32.const 0)
                     )
                     (i32.eqz
                      (local.get $12)
                     )
                    )
                   )
                  )
                  (local.set $10
                   (local.get $12)
                  )
                  (local.set $17
                   (local.get $6)
                  )
                  (loop $label14
                   (local.set $13
                    (if (result i32)
                     (local.tee $6
                      (i32.load offset=8
                       (local.get $10)
                      )
                     )
                     (then
                      (i32.store
                       (local.get $6)
                       (local.tee $6
                        (i32.add
                         (i32.load
                          (local.get $6)
                         )
                         (i32.const 1)
                        )
                       )
                      )
                      (br_if $block2
                       (i32.eqz
                        (local.get $6)
                       )
                      )
                      (i32.load offset=8
                       (local.get $10)
                      )
                     )
                     (else
                      (i32.const 0)
                     )
                    )
                   )
                   (if
                    (local.tee $6
                     (call $dlmalloc
                      (i32.const 16)
                     )
                    )
                    (then
                     (i32.store offset=12
                      (local.get $6)
                      (local.get $17)
                     )
                     (i32.store offset=8
                      (local.get $6)
                      (local.get $13)
                     )
                     (i64.store align=4
                      (local.get $6)
                      (i64.const 4294967297)
                     )
                     (local.set $17
                      (local.get $6)
                     )
                     (br_if $block26
                      (i32.eqz
                       (local.tee $10
                        (i32.load offset=12
                         (local.get $10)
                        )
                       )
                      )
                     )
                     (br $label14)
                    )
                   )
                  )
                  (br $block11)
                 )
                 (i32.store offset=64
                  (local.get $8)
                  (i32.const 0)
                 )
                 (i32.store offset=60
                  (local.get $8)
                  (local.get $6)
                 )
                 (i32.const 1)
                )
               )
               (block $block28
                (if
                 (i32.le_u
                  (local.get $7)
                  (i32.const 1073741823)
                 )
                 (then
                  (br_if $block28
                   (i32.lt_u
                    (local.tee $6
                     (i32.shl
                      (local.get $7)
                      (i32.const 2)
                     )
                    )
                    (i32.const 2147483645)
                   )
                  )
                 )
                )
                (call $_RNvNtCsi9YzqDQQz2q_5alloc7raw_vec17capacity_overflow)
                (unreachable)
               )
               (block $block29
                (if
                 (i32.eqz
                  (local.get $6)
                 )
                 (then
                  (local.set $14
                   (i32.const 4)
                  )
                  (local.set $13
                   (i32.const 0)
                  )
                  (br $block29)
                 )
                )
                (local.set $13
                 (local.get $7)
                )
                (br_if $block30
                 (i32.eqz
                  (local.tee $14
                   (call $dlmalloc
                    (local.get $6)
                   )
                  )
                 )
                )
               )
               (block $block31
                (br_if $block31
                 (i32.eqz
                  (local.get $7)
                 )
                )
                (local.set $17
                 (i32.and
                  (local.get $7)
                  (i32.const 7)
                 )
                )
                (local.set $6
                 (i32.const 0)
                )
                (if
                 (i32.ge_u
                  (local.get $7)
                  (i32.const 8)
                 )
                 (then
                  (local.set $20
                   (i32.and
                    (local.get $7)
                    (i32.const 1073741816)
                   )
                  )
                  (local.set $10
                   (local.get $14)
                  )
                  (loop $label15
                   (i32.store
                    (local.get $10)
                    (local.get $6)
                   )
                   (i32.store
                    (i32.add
                     (local.get $10)
                     (i32.const 28)
                    )
                    (i32.add
                     (local.get $6)
                     (i32.const 7)
                    )
                   )
                   (i32.store
                    (i32.add
                     (local.get $10)
                     (i32.const 24)
                    )
                    (i32.add
                     (local.get $6)
                     (i32.const 6)
                    )
                   )
                   (i32.store
                    (i32.add
                     (local.get $10)
                     (i32.const 20)
                    )
                    (i32.add
                     (local.get $6)
                     (i32.const 5)
                    )
                   )
                   (i32.store
                    (i32.add
                     (local.get $10)
                     (i32.const 16)
                    )
                    (i32.add
                     (local.get $6)
                     (i32.const 4)
                    )
                   )
                   (i32.store
                    (i32.add
                     (local.get $10)
                     (i32.const 12)
                    )
                    (i32.add
                     (local.get $6)
                     (i32.const 3)
                    )
                   )
                   (i32.store
                    (i32.add
                     (local.get $10)
                     (i32.const 8)
                    )
                    (i32.add
                     (local.get $6)
                     (i32.const 2)
                    )
                   )
                   (i32.store
                    (i32.add
                     (local.get $10)
                     (i32.const 4)
                    )
                    (i32.add
                     (local.get $6)
                     (i32.const 1)
                    )
                   )
                   (local.set $10
                    (i32.add
                     (local.get $10)
                     (i32.const 32)
                    )
                   )
                   (br_if $label15
                    (i32.ne
                     (local.tee $6
                      (i32.add
                       (local.get $6)
                       (i32.const 8)
                      )
                     )
                     (local.get $20)
                    )
                   )
                  )
                  (br_if $block31
                   (i32.eqz
                    (local.get $17)
                   )
                  )
                 )
                )
                (local.set $10
                 (i32.add
                  (local.get $14)
                  (i32.shl
                   (local.get $6)
                   (i32.const 2)
                  )
                 )
                )
                (loop $label16
                 (i32.store
                  (local.get $10)
                  (local.get $6)
                 )
                 (local.set $10
                  (i32.add
                   (local.get $10)
                   (i32.const 4)
                  )
                 )
                 (local.set $6
                  (i32.add
                   (local.get $6)
                   (i32.const 1)
                  )
                 )
                 (br_if $label16
                  (local.tee $17
                   (i32.sub
                    (local.get $17)
                    (i32.const 1)
                   )
                  )
                 )
                )
               )
               (i32.store offset=76
                (local.get $8)
                (local.get $7)
               )
               (i32.store offset=72
                (local.get $8)
                (local.get $14)
               )
               (i32.store offset=68
                (local.get $8)
                (local.get $13)
               )
               (if
                (i32.eqz
                 (local.tee $7
                  (call $_ZN6matrix5zebra17hfa0b4bd4996b012aE
                   (i32.add
                    (local.get $8)
                    (i32.const 56)
                   )
                   (i32.add
                    (local.get $15)
                    (i32.const 8)
                   )
                   (local.get $18)
                   (i32.add
                    (local.get $8)
                    (i32.const 68)
                   )
                   (i32.const 1)
                  )
                 )
                )
                (then
                 (if
                  (local.get $13)
                  (then
                   (call $dlfree
                    (local.get $14)
                   )
                  )
                 )
                 (i32.store
                  (local.get $15)
                  (local.tee $6
                   (i32.sub
                    (i32.load
                     (local.get $15)
                    )
                    (i32.const 1)
                   )
                  )
                 )
                 (if
                  (i32.eqz
                   (local.get $6)
                  )
                  (then
                   (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
                    (i32.add
                     (local.get $8)
                     (i32.const 48)
                    )
                   )
                  )
                 )
                 (block $block32
                  (br_if $block32
                   (i32.eqz
                    (local.get $12)
                   )
                  )
                  (i32.store
                   (local.get $12)
                   (local.tee $6
                    (i32.sub
                     (i32.load
                      (local.get $12)
                     )
                     (i32.const 1)
                    )
                   )
                  )
                  (br_if $block32
                   (local.get $6)
                  )
                  (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
                   (local.get $16)
                  )
                 )
                 (i32.store
                  (local.get $9)
                  (local.tee $6
                   (i32.sub
                    (i32.load
                     (local.get $9)
                    )
                    (i32.const 1)
                   )
                  )
                 )
                 (br_if $block33
                  (local.get $6)
                 )
                 (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
                  (i32.add
                   (local.get $8)
                   (i32.const 28)
                  )
                 )
                 (br $block33)
                )
               )
               (if
                (local.get $13)
                (then
                 (call $dlfree
                  (local.get $14)
                 )
                )
               )
               (call $_ZN6matrix11Permutation7brother17h371b75b5f64de937E
                (i32.add
                 (local.get $8)
                 (i32.const 32)
                )
                (local.get $15)
                (local.get $12)
               )
               (i32.store
                (local.get $15)
                (local.tee $6
                 (i32.sub
                  (i32.load
                   (local.get $15)
                  )
                  (i32.const 1)
                 )
                )
               )
               (if
                (i32.eqz
                 (local.get $6)
                )
                (then
                 (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
                  (i32.add
                   (local.get $8)
                   (i32.const 48)
                  )
                 )
                )
               )
               (block $block34
                (br_if $block34
                 (i32.eqz
                  (local.get $12)
                 )
                )
                (i32.store
                 (local.get $12)
                 (local.tee $6
                  (i32.sub
                   (i32.load
                    (local.get $12)
                   )
                   (i32.const 1)
                  )
                 )
                )
                (br_if $block34
                 (local.get $6)
                )
                (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
                 (local.get $16)
                )
               )
               (if
                (i32.load offset=32
                 (local.get $8)
                )
                (then
                 (local.set $15
                  (i32.load offset=36
                   (local.get $8)
                  )
                 )
                 (i32.store offset=52
                  (local.get $8)
                  (local.tee $12
                   (i32.load offset=40
                    (local.get $8)
                   )
                  )
                 )
                 (i32.store offset=48
                  (local.get $8)
                  (local.get $15)
                 )
                 (br_if $block35
                  (i32.eqz
                   (local.get $15)
                  )
                 )
                 (br $label17)
                )
               )
              )
              (i32.store
               (local.get $9)
               (local.tee $6
                (i32.sub
                 (i32.load
                  (local.get $9)
                 )
                 (i32.const 1)
                )
               )
              )
              (if
               (i32.eqz
                (local.get $6)
               )
               (then
                (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
                 (i32.add
                  (local.get $8)
                  (i32.const 28)
                 )
                )
               )
              )
              (if
               (i32.eqz
                (local.tee $6
                 (i32.load offset=12
                  (local.get $11)
                 )
                )
               )
               (then
                (call $_ZN6matrix6search17hc9885ee55d90aef9E
                 (local.get $0)
                 (local.get $1)
                 (local.get $21)
                 (local.get $2)
                 (i32.const 0)
                 (local.get $5)
                )
                (br $block33)
               )
              )
              (i32.store
               (local.get $6)
               (local.tee $6
                (i32.add
                 (i32.load
                  (local.get $6)
                 )
                 (i32.const 1)
                )
               )
              )
              (br_if $block2
               (i32.eqz
                (local.get $6)
               )
              )
              (call $_ZN6matrix6search17hc9885ee55d90aef9E
               (local.get $0)
               (local.get $1)
               (local.get $21)
               (local.get $2)
               (i32.load offset=12
                (local.get $11)
               )
               (local.get $5)
              )
              (br $block33)
             )
             (call $_RNvNtCsdHhIpgkcIfN_4core6option13unwrap_failed
              (i32.const 1052156)
             )
             (unreachable)
            )
            (call $_RNvNtCsi9YzqDQQz2q_5alloc7raw_vec12handle_error
             (i32.const 4)
             (local.get $6)
            )
            (unreachable)
           )
           (br $block11)
          )
         )
         (br $block11)
        )
        (br_if $label18
         (local.tee $11
          (block (result i32)
           (local.set $scratch
            (if (result i32)
             (local.tee $6
              (i32.load offset=12
               (local.get $11)
              )
             )
             (then
              (i32.store
               (local.get $6)
               (local.tee $6
                (i32.add
                 (i32.load
                  (local.get $6)
                 )
                 (i32.const 1)
                )
               )
              )
              (br_if $block2
               (i32.eqz
                (local.get $6)
               )
              )
              (i32.load offset=12
               (local.get $11)
              )
             )
             (else
              (i32.const 0)
             )
            )
           )
           (block $block36
            (br_if $block36
             (local.get $7)
            )
            (i32.store
             (local.get $2)
             (local.tee $2
              (i32.sub
               (i32.load
                (local.get $2)
               )
               (i32.const 1)
              )
             )
            )
            (br_if $block36
             (local.get $2)
            )
            (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
             (i32.add
              (local.get $8)
              (i32.const 24)
             )
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
           (if
            (i32.eqz
             (local.get $2)
            )
            (then
             (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
              (i32.add
               (local.get $8)
               (i32.const 20)
              )
             )
            )
           )
           (local.get $scratch)
          )
         )
        )
       )
       (br $block21)
      )
      (call $_RNvNtCsi9YzqDQQz2q_5alloc7raw_vec12handle_error
       (i32.const 4)
       (i32.const 8)
      )
      (unreachable)
     )
     (i32.store
      (local.get $0)
      (i32.const 0)
     )
     (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
      (i32.add
       (local.get $8)
       (i32.const 32)
      )
     )
     (br $block21)
    )
    (block $block37
     (br_if $block37
      (i32.eqz
       (local.get $4)
      )
     )
     (i32.store
      (local.get $4)
      (local.tee $0
       (i32.sub
        (i32.load
         (local.get $4)
        )
        (i32.const 1)
       )
      )
     )
     (br_if $block37
      (local.get $0)
     )
     (call $_ZN5alloc2rc15Rc$LT$T$C$A$GT$9drop_slow17h0005018820e77e45E
      (i32.add
       (local.get $8)
       (i32.const 16)
      )
     )
    )
    (i32.store
     (local.get $3)
     (local.tee $0
      (i32.sub
       (i32.load
        (local.get $3)
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
        (local.get $8)
        (i32.const 12)
       )
      )
     )
    )
    (global.set $__stack_pointer
     (i32.add
      (local.get $8)
      (i32.const 80)
     )
    )
    (return)
   )
   (unreachable)
  )
  (call $_RNvNtCsi9YzqDQQz2q_5alloc5alloc18handle_alloc_error
   (i32.const 4)
   (i32.const 16)
  )
  (unreachable)
 )
