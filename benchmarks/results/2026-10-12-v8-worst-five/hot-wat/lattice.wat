;; Exact original optimized function $function28, import-inclusive index 125.
;; Full module and referenced definitions are retained in raw-artifacts.tar.xz.
(func $function28
  (type $30)
  (param $0 eqref)
  (param $1 eqref)
  (param $2 eqref)
  (param $3 nullref)
  (result eqref)
  (local $4 (ref $vector))
  (local $5 eqref)
  (local $6 eqref)
  (local $7 (ref $closure))
  (local $8 (ref null $closure))
  (local $9 i32)
  (local $10 i32)
  (local $11 i32)
  (local $12 i32)
  (local.set $11
    (block $block12
      (result i32)
      (block $block1
        (block $block
          (return
            (if
              (result eqref)
              (if
                (result i32)
                (ref.eq
                  (local.tee $5
                    (block $block2
                      (result eqref)
                      (br_if $block
                        (i32.or
                          (ref.is_null (local.get $2))
                          (ref.eq (local.get $2) (global.get $uninitialized))
                        )
                      )
                      (if
                        (ref.test (ref $values) (local.get $2))
                        (then
                          (br_if $block1
                            (i32.ne
                              (array.len
                                (local.tee $4 (struct.get $values 0 (ref.cast (ref $values) (local.get $2))))
                              )
                              (i32.const 1)
                            )
                          )
                          (br $block2 (array.get $vector (local.get $4) (i32.const 0)))
                        )
                      )
                      (local.get $2)
                    )
                  )
                  (global.get $nil)
                )
                (then (i32.const 1))
                (else
                  (drop
                    (if
                      (result i32)
                      (ref.test (ref $atom) (local.get $5))
                      (then
                        (i32.lt_s (struct.get $atom 0 (ref.cast (ref $atom) (local.get $5))) (i32.const 0))
                      )
                      (else (i32.const 0))
                    )
                  )
                  (i32.const 0)
                )
              )
              (then (global.get $false))
              (else
                (local.set $6
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
                              (local.tee $4 (struct.get $values 0 (ref.cast (ref $values) (local.get $1))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block3 (array.get $vector (local.get $4) (i32.const 0)))
                      )
                    )
                    (local.get $1)
                  )
                )
                (local.set $5
                  (block $block5
                    (result eqref)
                    (if
                      (ref.test
                        (ref $values)
                        (local.tee $5
                          (struct.get $pair 0
                            (ref.cast
                              (ref $pair)
                              (block $block4
                                (result eqref)
                                (br_if $block
                                  (i32.or
                                    (ref.is_null (local.get $2))
                                    (ref.eq (local.get $2) (global.get $uninitialized))
                                  )
                                )
                                (if
                                  (ref.test (ref $values) (local.get $2))
                                  (then
                                    (br_if $block1
                                      (i32.ne
                                        (array.len
                                          (local.tee $4
                                            (struct.get $values 0 (ref.cast (ref $values) (local.get $2)))
                                          )
                                        )
                                        (i32.const 1)
                                      )
                                    )
                                    (br $block4 (array.get $vector (local.get $4) (i32.const 0)))
                                  )
                                )
                                (local.get $2)
                              )
                            )
                          )
                        )
                      )
                      (then
                        (br_if $block1
                          (i32.ne
                            (array.len
                              (local.tee $4 (struct.get $values 0 (ref.cast (ref $values) (local.get $5))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block5 (array.get $vector (local.get $4) (i32.const 0)))
                      )
                    )
                    (local.get $5)
                  )
                )
                (if
                  (result eqref)
                  (ref.eq
                    (block $block7
                      (result eqref)
                      (if
                        (ref.test
                          (ref $values)
                          (local.tee $5
                            (call_ref $call
                              (struct.get $closure 1
                                (local.tee $7
                                  (ref.cast
                                    (ref $closure)
                                    (block $block6
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
                                                (local.tee $4
                                                  (struct.get $values 0
                                                    (ref.cast (ref $values) (local.get $0))
                                                  )
                                                )
                                              )
                                              (i32.const 1)
                                            )
                                          )
                                          (br $block6 (array.get $vector (local.get $4) (i32.const 0)))
                                        )
                                      )
                                      (local.get $0)
                                    )
                                  )
                                )
                              )
                              (array.new_fixed $vector 2 (local.get $6) (local.get $5))
                              (ref.null none)
                              (struct.get $closure 0 (local.get $7))
                            )
                          )
                        )
                        (then
                          (br_if $block1
                            (i32.ne
                              (array.len
                                (local.tee $4 (struct.get $values 0 (ref.cast (ref $values) (local.get $5))))
                              )
                              (i32.const 1)
                            )
                          )
                          (br $block7 (array.get $vector (local.get $4) (i32.const 0)))
                        )
                      )
                      (local.get $5)
                    )
                    (global.get $false)
                  )
                  (then
                    (return_call $function28
                      (block $block8
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
                                  (local.tee $4
                                    (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                  )
                                )
                                (i32.const 1)
                              )
                            )
                            (br $block8 (array.get $vector (local.get $4) (i32.const 0)))
                          )
                        )
                        (local.get $0)
                      )
                      (block $block9
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
                                  (local.tee $4
                                    (struct.get $values 0 (ref.cast (ref $values) (local.get $1)))
                                  )
                                )
                                (i32.const 1)
                              )
                            )
                            (br $block9 (array.get $vector (local.get $4) (i32.const 0)))
                          )
                        )
                        (local.get $1)
                      )
                      (block $block11
                        (result eqref)
                        (if
                          (ref.test
                            (ref $values)
                            (local.tee $0
                              (struct.get $pair 1
                                (ref.cast
                                  (ref $pair)
                                  (block $block10
                                    (result eqref)
                                    (br_if $block
                                      (i32.or
                                        (ref.is_null (local.get $2))
                                        (ref.eq (local.get $2) (global.get $uninitialized))
                                      )
                                    )
                                    (if
                                      (ref.test (ref $values) (local.get $2))
                                      (then
                                        (br_if $block1
                                          (i32.ne
                                            (array.len
                                              (local.tee $4
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $2)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block10 (array.get $vector (local.get $4) (i32.const 0)))
                                      )
                                    )
                                    (local.get $2)
                                  )
                                )
                              )
                            )
                          )
                          (then
                            (br_if $block1
                              (i32.ne
                                (array.len
                                  (local.tee $4
                                    (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                  )
                                )
                                (i32.const 1)
                              )
                            )
                            (br $block11 (array.get $vector (local.get $4) (i32.const 0)))
                          )
                        )
                        (local.get $0)
                      )
                      (block
                        (result nullref)
                        (br_if $block (ref.is_null (local.tee $8 (global.get $g195))))
                        (drop (ref.as_non_null (local.get $8)))
                        (local.get $3)
                      )
                    )
                  )
                  (else
                    (br_if $block
                      (i32.or
                        (ref.is_null (local.get $2))
                        (ref.eq (local.get $2) (global.get $uninitialized))
                      )
                    )
                    (local.get $2)
                  )
                )
              )
            )
          )
        )
        (global.set $error_code (i32.const 6))
        (local.set $10 (i32.load (i32.const 1062312)))
        (br $block12 (i32.load (i32.const 1062352)))
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
