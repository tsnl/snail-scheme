(func $function58
  (type $35)
  (param $0 (ref $vector))
  (param $1 (ref eq))
  (param $2 (ref null $result_context))
  (result eqref)
  (local $3 eqref)
  (local $4 eqref)
  (local $5 eqref)
  (local $6 (ref $vector))
  (local $7 (ref $vector))
  (local $8 (ref struct))
  (local $9 i32)
  (local $10 i32)
  (local $11 i32)
  (local $12 i32)
  (local $13 i64)
  (local.set $11
    (block $block3
      (result i32)
      (block $block1
        (block $block
          (br_if $block
            (i32.or
              (ref.is_null (local.tee $4 (array.get $vector (local.get $0) (i32.const 0))))
              (ref.eq (local.get $4) (global.get $uninitialized))
            )
          )
          (local.set $9
            (i32.wrap_i64
              (if
                (result i64)
                (ref.test
                  (ref i31)
                  (local.tee $3
                    (block $block2
                      (result eqref)
                      (br_if $block
                        (i32.or
                          (ref.is_null (local.tee $3 (array.get $vector (local.get $0) (i32.const 1))))
                          (ref.eq (local.get $3) (global.get $uninitialized))
                        )
                      )
                      (if
                        (ref.test (ref $values) (local.get $3))
                        (then
                          (br_if $block1
                            (i32.ne
                              (array.len
                                (local.tee $6 (struct.get $values 0 (ref.cast (ref $values) (local.get $3))))
                              )
                              (i32.const 1)
                            )
                          )
                          (br $block2 (array.get $vector (local.get $6) (i32.const 0)))
                        )
                      )
                      (local.get $3)
                    )
                  )
                )
                (then (i64.extend_i32_s (i31.get_s (ref.cast (ref i31) (local.get $3)))))
                (else
                  (if
                    (result i64)
                    (ref.test (ref $integer) (local.get $3))
                    (then (struct.get $integer 0 (ref.cast (ref $integer) (local.get $3))))
                    (else
                      (global.set $error_code (i32.const 1))
                      (local.set $10 (i32.load (i32.const 1062292)))
                      (br $block3 (i32.load (i32.const 1062332)))
                    )
                  )
                )
              )
            )
          )
          (local.set $3
            (block $block5
              (result eqref)
              (if
                (ref.test
                  (ref $values)
                  (local.tee $3
                    (struct.get $pair 0
                      (ref.cast
                        (ref $pair)
                        (block $block4
                          (result eqref)
                          (br_if $block
                            (i32.or
                              (ref.is_null (local.tee $3 (array.get $vector (local.get $0) (i32.const 2))))
                              (ref.eq (local.get $3) (global.get $uninitialized))
                            )
                          )
                          (if
                            (ref.test (ref $values) (local.get $3))
                            (then
                              (br_if $block1
                                (i32.ne
                                  (array.len
                                    (local.tee $6
                                      (struct.get $values 0 (ref.cast (ref $values) (local.get $3)))
                                    )
                                  )
                                  (i32.const 1)
                                )
                              )
                              (br $block4 (array.get $vector (local.get $6) (i32.const 0)))
                            )
                          )
                          (local.get $3)
                        )
                      )
                    )
                  )
                )
                (then
                  (br_if $block1
                    (i32.ne
                      (array.len
                        (local.tee $6 (struct.get $values 0 (ref.cast (ref $values) (local.get $3))))
                      )
                      (i32.const 1)
                    )
                  )
                  (br $block5 (array.get $vector (local.get $6) (i32.const 0)))
                )
              )
              (local.get $3)
            )
          )
          (br_if $block (ref.eq (local.get $1) (global.get $uninitialized)))
          (array.copy $vector $vector
            (ref.cast (ref $vector) (local.get $4))
            (local.get $9)
            (ref.cast (ref $vector) (local.get $3))
            (i32.const 0)
            (i32.wrap_i64
              (if
                (result i64)
                (ref.test (ref i31) (local.get $1))
                (then (i64.extend_i32_s (i31.get_s (ref.cast (ref i31) (local.get $1)))))
                (else (struct.get $integer 0 (ref.cast (ref $integer) (local.get $1))))
              )
            )
          )
          (local.set $3
            (block $block7
              (result eqref)
              (if
                (ref.test
                  (ref $values)
                  (local.tee $3
                    (struct.get $pair 1
                      (ref.cast
                        (ref $pair)
                        (block $block6
                          (result eqref)
                          (br_if $block
                            (i32.or
                              (ref.is_null (local.tee $3 (array.get $vector (local.get $0) (i32.const 2))))
                              (ref.eq (local.get $3) (global.get $uninitialized))
                            )
                          )
                          (if
                            (ref.test (ref $values) (local.get $3))
                            (then
                              (br_if $block1
                                (i32.ne
                                  (array.len
                                    (local.tee $6
                                      (struct.get $values 0 (ref.cast (ref $values) (local.get $3)))
                                    )
                                  )
                                  (i32.const 1)
                                )
                              )
                              (br $block6 (array.get $vector (local.get $6) (i32.const 0)))
                            )
                          )
                          (local.get $3)
                        )
                      )
                    )
                  )
                )
                (then
                  (br_if $block1
                    (i32.ne
                      (array.len
                        (local.tee $6 (struct.get $values 0 (ref.cast (ref $values) (local.get $3))))
                      )
                      (i32.const 1)
                    )
                  )
                  (br $block7 (array.get $vector (local.get $6) (i32.const 0)))
                )
              )
              (local.get $3)
            )
          )
          (local.set $5
            (if
              (result eqref)
              (i32.and
                (ref.test
                  (ref i31)
                  (local.tee $4
                    (block $block8
                      (result eqref)
                      (br_if $block
                        (i32.or
                          (ref.is_null (local.tee $4 (array.get $vector (local.get $0) (i32.const 1))))
                          (ref.eq (local.get $4) (global.get $uninitialized))
                        )
                      )
                      (if
                        (ref.test (ref $values) (local.get $4))
                        (then
                          (br_if $block1
                            (i32.ne
                              (array.len
                                (local.tee $6 (struct.get $values 0 (ref.cast (ref $values) (local.get $4))))
                              )
                              (i32.const 1)
                            )
                          )
                          (br $block8 (array.get $vector (local.get $6) (i32.const 0)))
                        )
                      )
                      (local.get $4)
                    )
                  )
                )
                (block
                  (result i32)
                  (br_if $block (ref.eq (local.get $1) (global.get $uninitialized)))
                  (ref.test (ref i31) (local.get $1))
                )
              )
              (then
                (if
                  (result eqref)
                  (i32.le_u
                    (i32.add
                      (local.tee $9
                        (i32.add
                          (i31.get_s (ref.cast (ref i31) (local.get $4)))
                          (i31.get_s (ref.cast (ref i31) (local.get $1)))
                        )
                      )
                      (i32.const 1073741824)
                    )
                    (i32.const 2147483647)
                  )
                  (then (ref.i31 (local.get $9)))
                  (else (call $cold.checked_add (local.get $4) (local.get $1)))
                )
              )
              (else (call $cold.checked_add (local.get $4) (local.get $1)))
            )
          )
          (br_if $block
            (ref.eq
              (local.tee $8
                (struct.get $cell 0 (ref.cast (ref $cell) (array.get $vector (local.get $0) (i32.const 3))))
              )
              (global.get $uninitialized)
            )
          )
          (local.set $6 (struct.get $closure 1 (ref.cast (ref $closure) (local.get $8))))
          (return
            (if
              (result eqref)
              (if
                (result i32)
                (ref.eq
                  (local.tee $4
                    (block $block9
                      (result eqref)
                      (br_if $block
                        (i32.or
                          (ref.is_null (local.get $3))
                          (ref.eq (local.get $3) (global.get $uninitialized))
                        )
                      )
                      (if
                        (ref.test (ref $values) (local.get $3))
                        (then
                          (br_if $block1
                            (i32.ne
                              (array.len
                                (local.tee $7 (struct.get $values 0 (ref.cast (ref $values) (local.get $3))))
                              )
                              (i32.const 1)
                            )
                          )
                          (br $block9 (array.get $vector (local.get $7) (i32.const 0)))
                        )
                      )
                      (local.get $3)
                    )
                  )
                  (global.get $nil)
                )
                (then (i32.const 1))
                (else
                  (drop
                    (if
                      (result i32)
                      (ref.test (ref $atom) (local.get $4))
                      (then
                        (i32.lt_s (struct.get $atom 0 (ref.cast (ref $atom) (local.get $4))) (i32.const 0))
                      )
                      (else (i32.const 0))
                    )
                  )
                  (i32.const 0)
                )
              )
              (then
                (br_if $block
                  (i32.or
                    (ref.is_null (local.tee $3 (array.get $vector (local.get $6) (i32.const 0))))
                    (ref.eq (local.get $3) (global.get $uninitialized))
                  )
                )
                (local.get $3)
              )
              (else
                (local.set $1
                  (if
                    (result (ref eq))
                    (i64.le_u
                      (local.tee $13
                        (i64.extend_i32_u
                          (array.len
                            (ref.cast
                              (ref $vector)
                              (block $block11
                                (result eqref)
                                (if
                                  (ref.test
                                    (ref $values)
                                    (local.tee $4
                                      (struct.get $pair 0
                                        (ref.cast
                                          (ref $pair)
                                          (block $block10
                                            (result eqref)
                                            (br_if $block
                                              (i32.or
                                                (ref.is_null (local.get $3))
                                                (ref.eq (local.get $3) (global.get $uninitialized))
                                              )
                                            )
                                            (if
                                              (ref.test (ref $values) (local.get $3))
                                              (then
                                                (br_if $block1
                                                  (i32.ne
                                                    (array.len
                                                      (local.tee $7
                                                        (struct.get $values 0
                                                          (ref.cast (ref $values) (local.get $3))
                                                        )
                                                      )
                                                    )
                                                    (i32.const 1)
                                                  )
                                                )
                                                (br $block10 (array.get $vector (local.get $7) (i32.const 0)))
                                              )
                                            )
                                            (local.get $3)
                                          )
                                        )
                                      )
                                    )
                                  )
                                  (then
                                    (br_if $block1
                                      (i32.ne
                                        (array.len
                                          (local.tee $7
                                            (struct.get $values 0 (ref.cast (ref $values) (local.get $4)))
                                          )
                                        )
                                        (i32.const 1)
                                      )
                                    )
                                    (br $block11 (array.get $vector (local.get $7) (i32.const 0)))
                                  )
                                )
                                (local.get $4)
                              )
                            )
                          )
                        )
                      )
                      (i64.const 1073741823)
                    )
                    (then (ref.i31 (i32.wrap_i64 (local.get $13))))
                    (else (struct.new $integer (local.get $13)))
                  )
                )
                (return_call $function58
                  (array.new_fixed $vector 4
                    (array.get $vector (local.get $6) (i32.const 0))
                    (local.get $5)
                    (local.get $3)
                    (array.get $vector (local.get $6) (i32.const 1))
                  )
                  (local.get $1)
                  (local.get $2)
                )
              )
            )
          )
        )
        (global.set $error_code (i32.const 6))
        (local.set $10 (i32.load (i32.const 1062312)))
        (br $block3 (i32.load (i32.const 1062352)))
      )
      (global.set $error_code (i32.const 5))
      (local.set $10 (i32.load (i32.const 1062308)))
      (i32.load (i32.const 1062348))
    )
  )
  (global.set $__stack_pointer (local.tee $9 (i32.sub (global.get $__stack_pointer) (i32.const 32))))
  (call $_RNvMNtCsi9YzqDQQz2q_5alloc6stringNtB2_6String15from_utf8_lossy
    (local.tee $12 (i32.add (local.get $9) (i32.const 12)))
    (local.get $11)
    (local.get $10)
  )
  (i64.store offset=24 (local.get $9) (i64.or (i64.extend_i32_u (local.get $12)) (i64.const 103079215104)))
  (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio7__eprint (i32.add (local.get $9) (i32.const 24)))
  (local.set $10 (i32.load offset=16 (local.get $9)))
  (if (i32.gt_s (i32.load offset=12 (local.get $9)) (i32.const 0)) (then (call $dlfree (local.get $10))))
  (call $_RNvNtCset5xJoy1xWQ_3std2rt7cleanup)
  (call $__imported_wasi_snapshot_preview1_proc_exit (i32.const 1))
  (unreachable)
)
