(func $adapter54
  (type $call)
  (param $0 eqref)
  (param $1 (ref $vector))
  (param $2 (ref null $result_context))
  (result eqref)
  (local $3 i32)
  (local $4 i32)
  (local $5 i32)
  (local $6 i32)
  (local $7 i64)
  (local $8 (ref struct))
  (local $9 (ref null $closure))
  (local.set $3 (array.len (local.get $1)))
  (local.set $8 (global.get $nil))
  (loop $label
    (if
      (local.get $3)
      (then
        (local.set $8
          (struct.new $pair
            (array.get $vector (local.get $1) (local.tee $3 (i32.sub (local.get $3) (i32.const 1))))
            (local.get $8)
          )
        )
        (br $label)
      )
    )
  )
  (local.set $5
    (block $block1
      (result i32)
      (block $block
        (br_if $block (ref.eq (local.get $8) (global.get $uninitialized)))
        (br_if $block (ref.is_null (local.tee $9 (global.get $g237))))
        (drop (ref.as_non_null (local.get $9)))
        (if
          (i64.gt_u
            (local.tee $7
              (if
                (result i64)
                (ref.test
                  (ref i31)
                  (local.tee $0
                    (block $block2
                      (result eqref)
                      (if
                        (ref.test
                          (ref $values)
                          (local.tee $0 (call $function51 (local.get $8) (ref.null none)))
                        )
                        (then
                          (if
                            (i32.ne
                              (array.len
                                (local.tee $1 (struct.get $values 0 (ref.cast (ref $values) (local.get $0))))
                              )
                              (i32.const 1)
                            )
                            (then
                              (global.set $error_code (i32.const 5))
                              (local.set $4 (i32.load (i32.const 1062308)))
                              (br $block1 (i32.load (i32.const 1062348)))
                            )
                          )
                          (br $block2 (array.get $vector (local.get $1) (i32.const 0)))
                        )
                      )
                      (local.get $0)
                    )
                  )
                )
                (then (i64.extend_i32_s (i31.get_s (ref.cast (ref i31) (local.get $0)))))
                (else
                  (if
                    (result i64)
                    (ref.test (ref $integer) (local.get $0))
                    (then (struct.get $integer 0 (ref.cast (ref $integer) (local.get $0))))
                    (else
                      (global.set $error_code (i32.const 1))
                      (local.set $4 (i32.load (i32.const 1062292)))
                      (br $block1 (i32.load (i32.const 1062332)))
                    )
                  )
                )
              )
            )
            (i64.const 2147483647)
          )
          (then
            (global.set $error_code (i32.const 3))
            (local.set $4 (i32.load (i32.const 1062300)))
            (br $block1 (i32.load (i32.const 1062340)))
          )
        )
        (return_call $function55
          (array.new_fixed $vector 1 (local.get $8))
          (array.new $vector (global.get $unspecified) (i32.wrap_i64 (local.get $7)))
          (local.get $2)
        )
      )
      (global.set $error_code (i32.const 6))
      (local.set $4 (i32.load (i32.const 1062312)))
      (i32.load (i32.const 1062352))
    )
  )
  (global.set $__stack_pointer (local.tee $3 (i32.sub (global.get $__stack_pointer) (i32.const 32))))
  (call $_RNvMNtCsi9YzqDQQz2q_5alloc6stringNtB2_6String15from_utf8_lossy
    (local.tee $6 (i32.add (local.get $3) (i32.const 12)))
    (local.get $5)
    (local.get $4)
  )
  (i64.store offset=24 (local.get $3) (i64.or (i64.extend_i32_u (local.get $6)) (i64.const 103079215104)))
  (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio7__eprint (i32.add (local.get $3) (i32.const 24)))
  (local.set $4 (i32.load offset=16 (local.get $3)))
  (if (i32.gt_s (i32.load offset=12 (local.get $3)) (i32.const 0)) (then (call $dlfree (local.get $4))))
  (call $_RNvNtCset5xJoy1xWQ_3std2rt7cleanup)
  (call $__imported_wasi_snapshot_preview1_proc_exit (i32.const 1))
  (unreachable)
)
