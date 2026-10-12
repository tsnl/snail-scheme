(func $specialized349
  (type $24)
  (param $0 (ref $vector))
  (param $1 (ref $vector))
  (param $2 (ref $vector))
  (param $3 (ref null $result_context))
  (result eqref)
  (local $4 eqref)
  (local $5 (ref null $closure))
  (local $6 (ref $cell))
  (local $7 (ref null $result_checks))
  (local $8 (ref $result_context))
  (local $9 (ref $result_context))
  (local $10 (ref $pair))
  (local $11 (ref struct))
  (local $12 (ref $closure))
  (local $13 i32)
  (local $14 i32)
  (local $15 i32)
  (local $16 i32)
  (local $17 i64)
  (local.set $15
    (block $block6
      (result i32)
      (block $block1
        (block $block4
          (block $block
            (br_if $block (ref.is_null (local.tee $5 (global.get $g238))))
            (block $block3
              (if
                (ref.is_null (local.get $3))
                (then
                  (struct.set $result_context 0
                    (local.tee $8 (struct.new_default $result_context))
                    (call $defer_result_check (struct.get $result_context 0 (local.get $8)))
                  )
                  (drop (ref.as_non_null (local.get $5)))
                  (br_if $block (ref.is_null (local.tee $5 (global.get $g237))))
                  (drop (ref.as_non_null (local.get $5)))
                  (local.set $4
                    (call $function55
                      (array.new_fixed $vector 1
                        (local.tee $10
                          (struct.new $pair
                            (local.get $0)
                            (struct.new $pair
                              (local.get $1)
                              (struct.new $pair (local.get $2) (global.get $nil))
                            )
                          )
                        )
                      )
                      (block
                        (result (ref (exact $vector)))
                        (br_if $block4
                          (i64.gt_u
                            (local.tee $17
                              (if
                                (result i64)
                                (ref.test
                                  (ref i31)
                                  (local.tee $4
                                    (block $block2
                                      (result eqref)
                                      (struct.set $cell 0
                                        (local.tee $6 (struct.new $cell (global.get $uninitialized)))
                                        (struct.new $closure
                                          (ref.func $adapter53)
                                          (array.new_fixed $vector 1 (local.get $6))
                                        )
                                      )
                                      (br_if $block
                                        (ref.eq
                                          (local.tee $11 (struct.get $cell 0 (local.get $6)))
                                          (global.get $uninitialized)
                                        )
                                      )
                                      (if
                                        (ref.test
                                          (ref $values)
                                          (local.tee $4
                                            (call_ref $call
                                              (struct.get $closure 1
                                                (local.tee $12 (ref.cast (ref $closure) (local.get $11)))
                                              )
                                              (array.new_fixed $vector 2
                                                (local.get $10)
                                                (ref.i31 (i32.const 0))
                                              )
                                              (ref.null none)
                                              (struct.get $closure 0 (local.get $12))
                                            )
                                          )
                                        )
                                        (then
                                          (br_if $block1
                                            (i32.ne
                                              (array.len
                                                (local.tee $0
                                                  (struct.get $values 0
                                                    (ref.cast (ref $values) (local.get $4))
                                                  )
                                                )
                                              )
                                              (i32.const 1)
                                            )
                                          )
                                          (br $block2 (array.get $vector (local.get $0) (i32.const 0)))
                                        )
                                      )
                                      (local.get $4)
                                    )
                                  )
                                )
                                (then (i64.extend_i32_s (i31.get_s (ref.cast (ref i31) (local.get $4)))))
                                (else
                                  (if
                                    (result i64)
                                    (ref.test (ref $integer) (local.get $4))
                                    (then (struct.get $integer 0 (ref.cast (ref $integer) (local.get $4))))
                                    (else (br $block3))
                                  )
                                )
                              )
                            )
                            (i64.const 2147483647)
                          )
                        )
                        (array.new $vector (global.get $unspecified) (i32.wrap_i64 (local.get $17)))
                      )
                      (local.get $8)
                    )
                  )
                  (local.set $7 (struct.get $result_context 0 (local.get $8)))
                  (loop $label
                    (if
                      (i32.eqz (ref.is_null (local.get $7)))
                      (then
                        (drop (struct.get $result_checks 0 (local.get $7)))
                        (if
                          (i32.eqz
                            (ref.test
                              (ref $vector)
                              (local.tee $4
                                (block $block5
                                  (result eqref)
                                  (if
                                    (ref.test (ref $values) (local.get $4))
                                    (then
                                      (br_if $block1
                                        (i32.ne
                                          (array.len
                                            (local.tee $0
                                              (struct.get $values 0 (ref.cast (ref $values) (local.get $4)))
                                            )
                                          )
                                          (i32.const 1)
                                        )
                                      )
                                      (br $block5 (array.get $vector (local.get $0) (i32.const 0)))
                                    )
                                  )
                                  (local.get $4)
                                )
                              )
                            )
                          )
                          (then
                            (global.set $error_code (i32.const 8))
                            (local.set $13 (i32.load (i32.const 1062320)))
                            (br $block6 (i32.load (i32.const 1062360)))
                          )
                        )
                        (local.set $7 (struct.get $result_checks 1 (local.get $7)))
                        (br $label)
                      )
                    )
                  )
                  (return (local.get $4))
                )
              )
              (struct.set $result_context 0
                (local.tee $9 (ref.as_non_null (local.get $3)))
                (call $defer_result_check (struct.get $result_context 0 (local.get $9)))
              )
              (drop (ref.as_non_null (local.get $5)))
              (br_if $block (ref.is_null (local.tee $5 (global.get $g237))))
              (drop (ref.as_non_null (local.get $5)))
              (return_call $function55
                (array.new_fixed $vector 1
                  (local.tee $10
                    (struct.new $pair
                      (local.get $0)
                      (struct.new $pair (local.get $1) (struct.new $pair (local.get $2) (global.get $nil)))
                    )
                  )
                )
                (block
                  (result (ref (exact $vector)))
                  (br_if $block4
                    (i64.gt_u
                      (local.tee $17
                        (if
                          (result i64)
                          (ref.test
                            (ref i31)
                            (local.tee $4
                              (block $block7
                                (result eqref)
                                (struct.set $cell 0
                                  (local.tee $6 (struct.new $cell (global.get $uninitialized)))
                                  (struct.new $closure
                                    (ref.func $adapter53)
                                    (array.new_fixed $vector 1 (local.get $6))
                                  )
                                )
                                (br_if $block
                                  (ref.eq
                                    (local.tee $11 (struct.get $cell 0 (local.get $6)))
                                    (global.get $uninitialized)
                                  )
                                )
                                (if
                                  (ref.test
                                    (ref $values)
                                    (local.tee $4
                                      (call_ref $call
                                        (struct.get $closure 1
                                          (local.tee $12 (ref.cast (ref $closure) (local.get $11)))
                                        )
                                        (array.new_fixed $vector 2 (local.get $10) (ref.i31 (i32.const 0)))
                                        (ref.null none)
                                        (struct.get $closure 0 (local.get $12))
                                      )
                                    )
                                  )
                                  (then
                                    (br_if $block1
                                      (i32.ne
                                        (array.len
                                          (local.tee $0
                                            (struct.get $values 0 (ref.cast (ref $values) (local.get $4)))
                                          )
                                        )
                                        (i32.const 1)
                                      )
                                    )
                                    (br $block7 (array.get $vector (local.get $0) (i32.const 0)))
                                  )
                                )
                                (local.get $4)
                              )
                            )
                          )
                          (then (i64.extend_i32_s (i31.get_s (ref.cast (ref i31) (local.get $4)))))
                          (else
                            (if
                              (result i64)
                              (ref.test (ref $integer) (local.get $4))
                              (then (struct.get $integer 0 (ref.cast (ref $integer) (local.get $4))))
                              (else (br $block3))
                            )
                          )
                        )
                      )
                      (i64.const 2147483647)
                    )
                  )
                  (array.new $vector (global.get $unspecified) (i32.wrap_i64 (local.get $17)))
                )
                (local.get $9)
              )
            )
            (global.set $error_code (i32.const 1))
            (local.set $13 (i32.load (i32.const 1062292)))
            (br $block6 (i32.load (i32.const 1062332)))
          )
          (global.set $error_code (i32.const 6))
          (local.set $13 (i32.load (i32.const 1062312)))
          (br $block6 (i32.load (i32.const 1062352)))
        )
        (global.set $error_code (i32.const 3))
        (local.set $13 (i32.load (i32.const 1062300)))
        (br $block6 (i32.load (i32.const 1062340)))
      )
      (global.set $error_code (i32.const 5))
      (local.set $13 (i32.load (i32.const 1062308)))
      (i32.load (i32.const 1062348))
    )
  )
  (global.set $__stack_pointer (local.tee $14 (i32.sub (global.get $__stack_pointer) (i32.const 32))))
  (call $_RNvMNtCsi9YzqDQQz2q_5alloc6stringNtB2_6String15from_utf8_lossy
    (local.tee $16 (i32.add (local.get $14) (i32.const 12)))
    (local.get $15)
    (local.get $13)
  )
  (i64.store offset=24 (local.get $14) (i64.or (i64.extend_i32_u (local.get $16)) (i64.const 103079215104)))
  (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio7__eprint (i32.add (local.get $14) (i32.const 24)))
  (local.set $13 (i32.load offset=16 (local.get $14)))
  (if (i32.gt_s (i32.load offset=12 (local.get $14)) (i32.const 0)) (then (call $dlfree (local.get $13))))
  (call $_RNvNtCset5xJoy1xWQ_3std2rt7cleanup)
  (call $__imported_wasi_snapshot_preview1_proc_exit (i32.const 1))
  (unreachable)
)
