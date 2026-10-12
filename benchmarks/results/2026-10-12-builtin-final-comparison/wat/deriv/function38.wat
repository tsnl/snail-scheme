(func $function38
  (type $34)
  (param $0 eqref)
  (param $1 eqref)
  (result (ref struct))
  (local $2 (ref $vector))
  (local $3 eqref)
  (local $4 (ref struct))
  (local $5 (ref $closure))
  (local $6 (ref null $closure))
  (local $7 i32)
  (local $8 i32)
  (local $9 i32)
  (local $10 i32)
  (local.set $9
    (block $block11
      (result i32)
      (block $block1
        (block $block
          (return
            (if
              (result (ref struct))
              (if
                (result i32)
                (ref.eq
                  (local.tee $3
                    (block $block2
                      (result eqref)
                      (br_if $block
                        (i32.or
                          (ref.is_null (local.get $1))
                          (ref.eq (local.get $1) (global.get $uninitialized))
                        )
                      )
                      (if
                        (ref.test (ref $values) (local.get $1))
                        (then
                          (br_if $block1
                            (i32.ne
                              (array.len
                                (local.tee $2 (struct.get $values 0 (ref.cast (ref $values) (local.get $1))))
                              )
                              (i32.const 1)
                            )
                          )
                          (br $block2 (array.get $vector (local.get $2) (i32.const 0)))
                        )
                      )
                      (local.get $1)
                    )
                  )
                  (global.get $nil)
                )
                (then (i32.const 1))
                (else
                  (drop
                    (if
                      (result i32)
                      (ref.test (ref $atom) (local.get $3))
                      (then
                        (i32.lt_s (struct.get $atom 0 (ref.cast (ref $atom) (local.get $3))) (i32.const 0))
                      )
                      (else (i32.const 0))
                    )
                  )
                  (i32.const 0)
                )
              )
              (then (global.get $nil))
              (else
                (local.set $3
                  (block $block4
                    (result eqref)
                    (if
                      (ref.test
                        (ref $values)
                        (local.tee $3
                          (struct.get $pair 0
                            (ref.cast
                              (ref $pair)
                              (block $block3
                                (result eqref)
                                (br_if $block
                                  (i32.or
                                    (ref.is_null (local.get $1))
                                    (ref.eq (local.get $1) (global.get $uninitialized))
                                  )
                                )
                                (if
                                  (ref.test (ref $values) (local.get $1))
                                  (then
                                    (br_if $block1
                                      (i32.ne
                                        (array.len
                                          (local.tee $2
                                            (struct.get $values 0 (ref.cast (ref $values) (local.get $1)))
                                          )
                                        )
                                        (i32.const 1)
                                      )
                                    )
                                    (br $block3 (array.get $vector (local.get $2) (i32.const 0)))
                                  )
                                )
                                (local.get $1)
                              )
                            )
                          )
                        )
                      )
                      (then
                        (br_if $block1
                          (i32.ne
                            (array.len
                              (local.tee $2 (struct.get $values 0 (ref.cast (ref $values) (local.get $3))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block4 (array.get $vector (local.get $2) (i32.const 0)))
                      )
                    )
                    (local.get $3)
                  )
                )
                (struct.new $pair
                  (block $block6
                    (result eqref)
                    (if
                      (ref.test
                        (ref $values)
                        (local.tee $3
                          (call_ref $call
                            (struct.get $closure 1
                              (local.tee $5
                                (ref.cast
                                  (ref $closure)
                                  (block $block5
                                    (result eqref)
                                    (br_if $block
                                      (i32.or
                                        (ref.is_null (local.get $0))
                                        (ref.eq (local.get $0) (global.get $uninitialized))
                                      )
                                    )
                                    (if
                                      (ref.test (ref $values) (local.get $0))
                                      (then
                                        (br_if $block1
                                          (i32.ne
                                            (array.len
                                              (local.tee $2
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block5 (array.get $vector (local.get $2) (i32.const 0)))
                                      )
                                    )
                                    (local.get $0)
                                  )
                                )
                              )
                            )
                            (array.new_fixed $vector 1 (local.get $3))
                            (ref.null none)
                            (struct.get $closure 0 (local.get $5))
                          )
                        )
                      )
                      (then
                        (br_if $block1
                          (i32.ne
                            (array.len
                              (local.tee $2 (struct.get $values 0 (ref.cast (ref $values) (local.get $3))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block6 (array.get $vector (local.get $2) (i32.const 0)))
                      )
                    )
                    (local.get $3)
                  )
                  (block
                    (result eqref)
                    (local.set $3
                      (block $block7
                        (result eqref)
                        (br_if $block
                          (i32.or
                            (ref.is_null (local.get $0))
                            (ref.eq (local.get $0) (global.get $uninitialized))
                          )
                        )
                        (if
                          (ref.test (ref $values) (local.get $0))
                          (then
                            (br_if $block1
                              (i32.ne
                                (array.len
                                  (local.tee $2
                                    (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                  )
                                )
                                (i32.const 1)
                              )
                            )
                            (br $block7 (array.get $vector (local.get $2) (i32.const 0)))
                          )
                        )
                        (local.get $0)
                      )
                    )
                    (local.set $0
                      (block $block9
                        (result eqref)
                        (if
                          (ref.test
                            (ref $values)
                            (local.tee $0
                              (struct.get $pair 1
                                (ref.cast
                                  (ref $pair)
                                  (block $block8
                                    (result eqref)
                                    (br_if $block
                                      (i32.or
                                        (ref.is_null (local.get $1))
                                        (ref.eq (local.get $1) (global.get $uninitialized))
                                      )
                                    )
                                    (if
                                      (ref.test (ref $values) (local.get $1))
                                      (then
                                        (br_if $block1
                                          (i32.ne
                                            (array.len
                                              (local.tee $2
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $1)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block8 (array.get $vector (local.get $2) (i32.const 0)))
                                      )
                                    )
                                    (local.get $1)
                                  )
                                )
                              )
                            )
                          )
                          (then
                            (br_if $block1
                              (i32.ne
                                (array.len
                                  (local.tee $2
                                    (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                  )
                                )
                                (i32.const 1)
                              )
                            )
                            (br $block9 (array.get $vector (local.get $2) (i32.const 0)))
                          )
                        )
                        (local.get $0)
                      )
                    )
                    (br_if $block (ref.is_null (local.tee $6 (global.get $g230))))
                    (drop (ref.as_non_null (local.get $6)))
                    (block $block10
                      (result eqref)
                      (if
                        (ref.test
                          (ref $values)
                          (local.tee $4 (call $function38 (local.get $3) (local.get $0)))
                        )
                        (then
                          (br_if $block1
                            (i32.ne
                              (array.len
                                (local.tee $2 (struct.get $values 0 (ref.cast (ref $values) (local.get $4))))
                              )
                              (i32.const 1)
                            )
                          )
                          (br $block10 (array.get $vector (local.get $2) (i32.const 0)))
                        )
                      )
                      (local.get $4)
                    )
                  )
                )
              )
            )
          )
        )
        (global.set $error_code (i32.const 6))
        (local.set $8 (i32.load (i32.const 1062312)))
        (br $block11 (i32.load (i32.const 1062352)))
      )
      (global.set $error_code (i32.const 5))
      (local.set $8 (i32.load (i32.const 1062308)))
      (i32.load (i32.const 1062348))
    )
  )
  (global.set $__stack_pointer (local.tee $7 (i32.sub (global.get $__stack_pointer) (i32.const 32))))
  (call $_RNvMNtCsi9YzqDQQz2q_5alloc6stringNtB2_6String15from_utf8_lossy
    (local.tee $10 (i32.add (local.get $7) (i32.const 12)))
    (local.get $9)
    (local.get $8)
  )
  (i64.store offset=24 (local.get $7) (i64.or (i64.extend_i32_u (local.get $10)) (i64.const 103079215104)))
  (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio7__eprint (i32.add (local.get $7) (i32.const 24)))
  (local.set $8 (i32.load offset=16 (local.get $7)))
  (if (i32.gt_s (i32.load offset=12 (local.get $7)) (i32.const 0)) (then (call $dlfree (local.get $8))))
  (call $_RNvNtCset5xJoy1xWQ_3std2rt7cleanup)
  (call $__imported_wasi_snapshot_preview1_proc_exit (i32.const 1))
  (unreachable)
)
