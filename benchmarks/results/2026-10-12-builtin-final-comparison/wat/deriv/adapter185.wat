(func $adapter185
  (type $call)
  (param $0 eqref)
  (param $1 (ref $vector))
  (param $2 nullref)
  (result eqref)
  (local $3 i32)
  (local $4 i32)
  (local $5 i32)
  (local $6 i32)
  (local $7 eqref)
  (local $8 (ref null $closure))
  (block $block
    (if
      (i32.or (i32.ne (local.tee $3 (array.len (local.get $1))) (i32.const 1)) (i32.eqz (local.get $3)))
      (then
        (global.set $error_code (i32.const 4))
        (local.set $4 (i32.load (i32.const 1062344)))
        (local.set $5 (i32.load (i32.const 1062304)))
        (br $block)
      )
    )
    (return
      (block $block6
        (result (ref $pair))
        (block $block2
          (block $block1
            (local.set $7
              (block $block3
                (result eqref)
                (br_if $block1
                  (i32.or
                    (ref.is_null (local.tee $0 (array.get $vector (local.get $1) (i32.const 0))))
                    (ref.eq (local.get $0) (global.get $uninitialized))
                  )
                )
                (if
                  (ref.test (ref $values) (local.get $0))
                  (then
                    (br_if $block2
                      (i32.ne
                        (array.len
                          (local.tee $1 (struct.get $values 0 (ref.cast (ref $values) (local.get $0))))
                        )
                        (i32.const 1)
                      )
                    )
                    (br $block3 (array.get $vector (local.get $1) (i32.const 0)))
                  )
                )
                (local.get $0)
              )
            )
            (br_if $block1 (ref.is_null (local.tee $8 (global.get $g306))))
            (drop (ref.as_non_null (local.get $8)))
            (local.set $7
              (block $block4
                (result eqref)
                (if
                  (ref.test (ref $values) (local.tee $7 (call $function184 (local.get $7))))
                  (then
                    (br_if $block2
                      (i32.ne
                        (array.len
                          (local.tee $1 (struct.get $values 0 (ref.cast (ref $values) (local.get $7))))
                        )
                        (i32.const 1)
                      )
                    )
                    (br $block4 (array.get $vector (local.get $1) (i32.const 0)))
                  )
                )
                (local.get $7)
              )
            )
            (local.set $0
              (block $block5
                (result eqref)
                (br_if $block1
                  (i32.or (ref.is_null (local.get $0)) (ref.eq (local.get $0) (global.get $uninitialized)))
                )
                (if
                  (ref.test (ref $values) (local.get $0))
                  (then
                    (br_if $block2
                      (i32.ne
                        (array.len
                          (local.tee $1 (struct.get $values 0 (ref.cast (ref $values) (local.get $0))))
                        )
                        (i32.const 1)
                      )
                    )
                    (br $block5 (array.get $vector (local.get $1) (i32.const 0)))
                  )
                )
                (local.get $0)
              )
            )
            (br_if $block1 (ref.is_null (local.tee $8 (global.get $g208))))
            (drop (ref.as_non_null (local.get $8)))
            (br $block6
              (struct.new $pair
                (global.get $literal18)
                (struct.new $pair (local.get $7) (struct.new $pair (local.get $0) (global.get $nil)))
              )
            )
          )
          (global.set $error_code (i32.const 6))
          (local.set $4 (i32.load (i32.const 1062352)))
          (local.set $5 (i32.load (i32.const 1062312)))
          (br $block)
        )
        (global.set $error_code (i32.const 5))
        (local.set $4 (i32.load (i32.const 1062348)))
        (local.set $5 (i32.load (i32.const 1062308)))
        (br $block)
      )
    )
  )
  (global.set $__stack_pointer (local.tee $3 (i32.sub (global.get $__stack_pointer) (i32.const 32))))
  (call $_RNvMNtCsi9YzqDQQz2q_5alloc6stringNtB2_6String15from_utf8_lossy
    (local.tee $6 (i32.add (local.get $3) (i32.const 12)))
    (local.get $4)
    (local.get $5)
  )
  (i64.store offset=24 (local.get $3) (i64.or (i64.extend_i32_u (local.get $6)) (i64.const 103079215104)))
  (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio7__eprint (i32.add (local.get $3) (i32.const 24)))
  (local.set $4 (i32.load offset=16 (local.get $3)))
  (if (i32.gt_s (i32.load offset=12 (local.get $3)) (i32.const 0)) (then (call $dlfree (local.get $4))))
  (call $_RNvNtCset5xJoy1xWQ_3std2rt7cleanup)
  (call $__imported_wasi_snapshot_preview1_proc_exit (i32.const 1))
  (unreachable)
)
