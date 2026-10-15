(func $_ZN9bv2string9roundtrip17hdc9d3af325a8c619E (param $0 i32) (result i32)
  (local $1 i32)
  (local $2 i32)
  (local $3 i32)
  (local $4 i32)
  (local $5 i32)
  (local $6 i32)
  (local $7 i32)
  (local $8 i32)
  (global.set $__stack_pointer
   (local.tee $1
    (i32.sub
     (global.get $__stack_pointer)
     (i32.const 32)
    )
   )
  )
  (call $_RNvNtNtCsdHhIpgkcIfN_4core3str8converts9from_utf8
   (i32.add
    (local.get $1)
    (i32.const 12)
   )
   (local.tee $8
    (i32.load offset=4
     (local.get $0)
    )
   )
   (i32.load offset=8
    (local.get $0)
   )
  )
  (block $block6
   (block $block4
    (block $block3
     (block $block2
      (block $block
       (if
        (i32.ne
         (i32.load offset=12
          (local.get $1)
         )
         (i32.const 1)
        )
        (then
         (br_if $block
          (i32.lt_s
           (local.tee $2
            (i32.load offset=20
             (local.get $1)
            )
           )
           (i32.const 0)
          )
         )
         (block $block1
          (if
           (i32.eqz
            (local.get $2)
           )
           (then
            (i64.store offset=16 align=4
             (local.get $1)
             (i64.const 1)
            )
            (local.set $6
             (i32.const 1)
            )
            (local.set $7
             (i32.const 1)
            )
            (br $block1)
           )
          )
          (local.set $3
           (i32.load offset=16
            (local.get $1)
           )
          )
          (br_if $block2
           (i32.eqz
            (local.tee $6
             (call $dlmalloc
              (local.get $2)
             )
            )
           )
          )
          (if
           (i32.eqz
            (local.tee $4
             (i32.eqz
              (local.get $2)
             )
            )
           )
           (then
            (memory.copy
             (local.get $6)
             (local.get $3)
             (local.get $2)
            )
           )
          )
          (br_if $block3
           (i32.eqz
            (local.tee $7
             (call $dlmalloc
              (local.get $2)
             )
            )
           )
          )
          (if
           (i32.eqz
            (local.get $4)
           )
           (then
            (memory.copy
             (local.get $7)
             (local.get $3)
             (local.get $2)
            )
           )
          )
          (call $_RNvNtNtCsdHhIpgkcIfN_4core3str8converts9from_utf8
           (i32.add
            (local.get $1)
            (i32.const 12)
           )
           (local.get $7)
           (local.get $2)
          )
          (br_if $block4
           (i32.eq
            (i32.load offset=12
             (local.get $1)
            )
            (i32.const 1)
           )
          )
         )
         (br_if $block
          (i32.lt_s
           (local.tee $3
            (i32.load offset=20
             (local.get $1)
            )
           )
           (i32.const 0)
          )
         )
         (block $block5
          (if
           (i32.eqz
            (local.get $3)
           )
           (then
            (local.set $4
             (i32.const 1)
            )
            (br $block5)
           )
          )
          (local.set $5
           (i32.load offset=16
            (local.get $1)
           )
          )
          (br_if $block6
           (i32.eqz
            (local.tee $4
             (call $dlmalloc
              (local.get $3)
             )
            )
           )
          )
          (br_if $block5
           (i32.eqz
            (local.get $3)
           )
          )
          (memory.copy
           (local.get $4)
           (local.get $5)
           (local.get $3)
          )
         )
         (local.set $5
          (i32.const 0)
         )
         (if
          (i32.eq
           (local.get $2)
           (local.get $3)
          )
          (then
           (local.set $5
            (i32.eqz
             (call $memcmp
              (local.get $6)
              (local.get $4)
              (local.get $2)
             )
            )
           )
          )
         )
         (if
          (local.get $3)
          (then
           (call $dlfree
            (local.get $4)
           )
          )
         )
         (if
          (local.get $2)
          (then
           (call $dlfree
            (local.get $7)
           )
           (call $dlfree
            (local.get $6)
           )
          )
         )
         (if
          (i32.load
           (local.get $0)
          )
          (then
           (call $dlfree
            (local.get $8)
           )
          )
         )
         (global.set $__stack_pointer
          (i32.add
           (local.get $1)
           (i32.const 32)
          )
         )
         (return
          (local.get $5)
         )
        )
       )
       (i64.store offset=24
        (local.get $1)
        (i64.load offset=16 align=4
         (local.get $1)
        )
       )
       (call $_RNvNtCsdHhIpgkcIfN_4core6result13unwrap_failed
        (i32.const 1058848)
        (i32.const 43)
        (i32.add
         (local.get $1)
         (i32.const 24)
        )
        (i32.const 1051736)
        (i32.const 1051768)
       )
       (unreachable)
      )
      (call $_RNvNtCsi9YzqDQQz2q_5alloc7raw_vec17capacity_overflow)
      (unreachable)
     )
     (call $_RNvNtCsi9YzqDQQz2q_5alloc7raw_vec12handle_error
      (i32.const 1)
      (local.get $2)
     )
     (unreachable)
    )
    (call $_RNvNtCsi9YzqDQQz2q_5alloc7raw_vec12handle_error
     (i32.const 1)
     (local.get $2)
    )
    (unreachable)
   )
   (i64.store offset=24
    (local.get $1)
    (i64.load offset=16 align=4
     (local.get $1)
    )
   )
   (call $_RNvNtCsdHhIpgkcIfN_4core6result13unwrap_failed
    (i32.const 1058848)
    (i32.const 43)
    (i32.add
     (local.get $1)
     (i32.const 24)
    )
    (i32.const 1051736)
    (i32.const 1051752)
   )
   (unreachable)
  )
  (call $_RNvNtCsi9YzqDQQz2q_5alloc7raw_vec12handle_error
   (i32.const 1)
   (local.get $3)
  )
  (unreachable)
 )
