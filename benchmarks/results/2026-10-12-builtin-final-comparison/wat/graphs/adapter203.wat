(func $adapter203
  (type $call)
  (param $0 eqref)
  (param $1 (ref $vector))
  (param $2 nullref)
  (result eqref)
  (local $3 eqref)
  (local $4 eqref)
  (local $5 (ref $vector))
  (local $6 (ref $pair))
  (local $7 (ref struct))
  (local $8 i32)
  (local $9 i32)
  (local $10 i32)
  (local $11 i32)
  (local.set $10
    (block $block
      (result i32)
      (if
        (i32.or (i32.ne (local.tee $8 (array.len (local.get $1))) (i32.const 1)) (i32.eqz (local.get $8)))
        (then
          (global.set $error_code (i32.const 4))
          (local.set $9 (i32.load (i32.const 1062304)))
          (br $block (i32.load (i32.const 1062344)))
        )
      )
      (local.set $3 (array.get $vector (local.get $1) (i32.const 0)))
      (block $block2
        (block $block1
          (br_if $block1
            (i32.or
              (ref.is_null
                (local.tee $0
                  (array.get $vector (local.tee $1 (ref.cast (ref $vector) (local.get $0))) (i32.const 1))
                )
              )
              (ref.eq (local.get $0) (global.get $uninitialized))
            )
          )
          (br_if $block1
            (i32.or
              (ref.is_null (local.tee $4 (array.get $vector (local.get $1) (i32.const 2))))
              (ref.eq (local.get $4) (global.get $uninitialized))
            )
          )
          (local.set $6
            (struct.new $pair
              (local.get $4)
              (block $block3
                (result eqref)
                (br_if $block1
                  (i32.or
                    (ref.is_null (local.tee $4 (array.get $vector (local.get $1) (i32.const 3))))
                    (ref.eq (local.get $4) (global.get $uninitialized))
                  )
                )
                (if
                  (ref.test (ref $values) (local.get $4))
                  (then
                    (br_if $block2
                      (i32.ne
                        (array.len
                          (local.tee $5 (struct.get $values 0 (ref.cast (ref $values) (local.get $4))))
                        )
                        (i32.const 1)
                      )
                    )
                    (br $block3 (array.get $vector (local.get $5) (i32.const 0)))
                  )
                )
                (local.get $4)
              )
            )
          )
          (local.set $4
            (block $block4
              (result eqref)
              (br_if $block1
                (i32.or (ref.is_null (local.get $3)) (ref.eq (local.get $3) (global.get $uninitialized)))
              )
              (if
                (ref.test (ref $values) (local.get $3))
                (then
                  (br_if $block2
                    (i32.ne
                      (array.len
                        (local.tee $5 (struct.get $values 0 (ref.cast (ref $values) (local.get $3))))
                      )
                      (i32.const 1)
                    )
                  )
                  (br $block4 (array.get $vector (local.get $5) (i32.const 0)))
                )
              )
              (local.get $3)
            )
          )
          (br_if $block1
            (ref.eq
              (local.tee $7
                (struct.get $cell 0 (ref.cast (ref $cell) (array.get $vector (local.get $1) (i32.const 0))))
              )
              (global.get $uninitialized)
            )
          )
          (local.set $1 (struct.get $closure 1 (ref.cast (ref $closure) (local.get $7))))
          (local.set $3
            (block $block6
              (result eqref)
              (if
                (ref.test
                  (ref $values)
                  (local.tee $3
                    (struct.get $pair 0
                      (ref.cast
                        (ref $pair)
                        (block $block5
                          (result eqref)
                          (br_if $block1
                            (i32.or
                              (ref.is_null (local.get $0))
                              (ref.eq (local.get $0) (global.get $uninitialized))
                            )
                          )
                          (if
                            (ref.test (ref $values) (local.get $0))
                            (then
                              (br_if $block2
                                (i32.ne
                                  (array.len
                                    (local.tee $5
                                      (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                    )
                                  )
                                  (i32.const 1)
                                )
                              )
                              (br $block5 (array.get $vector (local.get $5) (i32.const 0)))
                            )
                          )
                          (local.get $0)
                        )
                      )
                    )
                  )
                )
                (then
                  (br_if $block2
                    (i32.ne
                      (array.len
                        (local.tee $5 (struct.get $values 0 (ref.cast (ref $values) (local.get $3))))
                      )
                      (i32.const 1)
                    )
                  )
                  (br $block6 (array.get $vector (local.get $5) (i32.const 0)))
                )
              )
              (local.get $3)
            )
          )
          (return_call $function199
            (array.new_fixed $vector 8
              (array.get $vector (local.get $1) (i32.const 0))
              (local.get $3)
              (array.get $vector (local.get $1) (i32.const 1))
              (local.get $4)
              (array.get $vector (local.get $1) (i32.const 2))
              (local.get $6)
              (array.get $vector (local.get $1) (i32.const 3))
              (array.get $vector (local.get $1) (i32.const 4))
            )
            (block $block8
              (result eqref)
              (if
                (ref.test
                  (ref $values)
                  (local.tee $0
                    (struct.get $pair 1
                      (ref.cast
                        (ref $pair)
                        (block $block7
                          (result eqref)
                          (br_if $block1
                            (i32.or
                              (ref.is_null (local.get $0))
                              (ref.eq (local.get $0) (global.get $uninitialized))
                            )
                          )
                          (if
                            (ref.test (ref $values) (local.get $0))
                            (then
                              (br_if $block2
                                (i32.ne
                                  (array.len
                                    (local.tee $1
                                      (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                    )
                                  )
                                  (i32.const 1)
                                )
                              )
                              (br $block7 (array.get $vector (local.get $1) (i32.const 0)))
                            )
                          )
                          (local.get $0)
                        )
                      )
                    )
                  )
                )
                (then
                  (br_if $block2
                    (i32.ne
                      (array.len
                        (local.tee $1 (struct.get $values 0 (ref.cast (ref $values) (local.get $0))))
                      )
                      (i32.const 1)
                    )
                  )
                  (br $block8 (array.get $vector (local.get $1) (i32.const 0)))
                )
              )
              (local.get $0)
            )
            (local.get $2)
          )
        )
        (global.set $error_code (i32.const 6))
        (local.set $9 (i32.load (i32.const 1062312)))
        (br $block (i32.load (i32.const 1062352)))
      )
      (global.set $error_code (i32.const 5))
      (local.set $9 (i32.load (i32.const 1062308)))
      (i32.load (i32.const 1062348))
    )
  )
  (global.set $__stack_pointer (local.tee $8 (i32.sub (global.get $__stack_pointer) (i32.const 32))))
  (call $_RNvMNtCsi9YzqDQQz2q_5alloc6stringNtB2_6String15from_utf8_lossy
    (local.tee $11 (i32.add (local.get $8) (i32.const 12)))
    (local.get $10)
    (local.get $9)
  )
  (i64.store offset=24 (local.get $8) (i64.or (i64.extend_i32_u (local.get $11)) (i64.const 103079215104)))
  (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio7__eprint (i32.add (local.get $8) (i32.const 24)))
  (local.set $9 (i32.load offset=16 (local.get $8)))
  (if (i32.gt_s (i32.load offset=12 (local.get $8)) (i32.const 0)) (then (call $dlfree (local.get $9))))
  (call $_RNvNtCset5xJoy1xWQ_3std2rt7cleanup)
  (call $__imported_wasi_snapshot_preview1_proc_exit (i32.const 1))
  (unreachable)
)
