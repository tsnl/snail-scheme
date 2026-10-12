(func $function420
  (type $28)
  (param $0 (ref $vector))
  (param $1 eqref)
  (param $2 nullref)
  (result eqref)
  (local $3 i32)
  (local $4 i32)
  (local $5 i32)
  (local $6 i32)
  (local $7 i64)
  (local $8 i64)
  (local $9 i64)
  (local $10 eqref)
  (local $11 eqref)
  (local $12 (ref null $closure))
  (local $13 (ref $vector))
  (local $14 (ref $vector))
  (local $15 (ref $vector))
  (local $16 (ref struct))
  (local.set $5
    (block $block1
      (result i32)
      (block $block2
        (block $block4
          (block $block
            (br_if $block
              (i32.or (ref.is_null (local.get $1)) (ref.eq (local.get $1) (global.get $uninitialized)))
            )
            (br_if $block (ref.is_null (local.tee $12 (global.get $g146))))
            (drop (ref.as_non_null (local.get $12)))
            (if
              (i32.or
                (i32.ne
                  (local.tee $3 (array.len (local.tee $15 (array.new_fixed $vector 1 (local.get $1)))))
                  (i32.const 1)
                )
                (i32.eqz (local.get $3))
              )
              (then
                (global.set $error_code (i32.const 4))
                (local.set $3 (i32.load (i32.const 1062304)))
                (br $block1 (i32.load (i32.const 1062344)))
              )
            )
            (block $block3
              (local.set $4
                (if
                  (result i32)
                  (ref.eq (array.get $vector (local.get $15) (i32.const 0)) (global.get $eof))
                  (then
                    (br_if $block
                      (i32.or
                        (ref.is_null (local.tee $1 (array.get $vector (local.get $0) (i32.const 0))))
                        (ref.eq (local.get $1) (global.get $uninitialized))
                      )
                    )
                    (br_if $block
                      (i32.or
                        (ref.is_null (local.tee $10 (array.get $vector (local.get $0) (i32.const 1))))
                        (ref.eq (local.get $10) (global.get $uninitialized))
                      )
                    )
                    (br_if $block
                      (i32.or
                        (ref.is_null (local.tee $11 (array.get $vector (local.get $0) (i32.const 2))))
                        (ref.eq (local.get $11) (global.get $uninitialized))
                      )
                    )
                    (br_if $block (ref.is_null (local.tee $12 (global.get $g208))))
                    (drop (ref.as_non_null (local.get $12)))
                    (return
                      (struct.new $pair
                        (local.get $1)
                        (struct.new $pair
                          (local.get $10)
                          (struct.new $pair (local.get $11) (global.get $nil))
                        )
                      )
                    )
                  )
                  (else
                    (br_if $block
                      (i32.or
                        (ref.is_null (local.get $1))
                        (ref.eq (local.get $1) (global.get $uninitialized))
                      )
                    )
                    (br_if $block2
                      (i32.lt_s
                        (local.tee $3 (struct.get $atom 0 (ref.cast (ref $atom) (local.get $1))))
                        (i32.const 256)
                      )
                    )
                    (if
                      (result i32)
                      (i32.eq (local.get $3) (i32.const 288))
                      (then
                        (br_if $block
                          (i32.or
                            (ref.is_null (local.tee $1 (array.get $vector (local.get $0) (i32.const 0))))
                            (ref.eq (local.get $1) (global.get $uninitialized))
                          )
                        )
                        (br_if $block
                          (i32.or
                            (ref.is_null (local.tee $10 (array.get $vector (local.get $0) (i32.const 1))))
                            (ref.eq (local.get $10) (global.get $uninitialized))
                          )
                        )
                        (br_if $block
                          (i32.or
                            (ref.is_null (local.tee $11 (array.get $vector (local.get $0) (i32.const 2))))
                            (ref.eq (local.get $11) (global.get $uninitialized))
                          )
                        )
                        (br_if $block3
                          (i64.lt_s
                            (i64.and
                              (i64.xor
                                (local.tee $7
                                  (i64.add
                                    (local.tee $8
                                      (if
                                        (result i64)
                                        (ref.test (ref i31) (local.get $11))
                                        (then
                                          (i64.extend_i32_s (i31.get_s (ref.cast (ref i31) (local.get $11))))
                                        )
                                        (else
                                          (struct.get $integer 0 (ref.cast (ref $integer) (local.get $11)))
                                        )
                                      )
                                    )
                                    (i64.const 1)
                                  )
                                )
                                (local.get $8)
                              )
                              (i64.xor (local.get $7) (i64.const 1))
                            )
                            (i64.const 0)
                          )
                        )
                        (i32.const 0)
                      )
                      (else
                        (br_if $block
                          (i32.or
                            (ref.is_null (local.get $1))
                            (ref.eq (local.get $1) (global.get $uninitialized))
                          )
                        )
                        (br_if $block2
                          (i32.lt_s
                            (local.tee $3 (struct.get $atom 0 (ref.cast (ref $atom) (local.get $1))))
                            (i32.const 256)
                          )
                        )
                        (if
                          (result i32)
                          (i32.eq (local.get $3) (i32.const 266))
                          (then
                            (br_if $block
                              (i32.or
                                (ref.is_null (local.tee $1 (array.get $vector (local.get $0) (i32.const 0))))
                                (ref.eq (local.get $1) (global.get $uninitialized))
                              )
                            )
                            (br_if $block3
                              (i64.lt_s
                                (i64.and
                                  (i64.xor
                                    (local.tee $7
                                      (i64.add
                                        (local.tee $8
                                          (if
                                            (result i64)
                                            (ref.test (ref i31) (local.get $1))
                                            (then
                                              (i64.extend_i32_s
                                                (i31.get_s (ref.cast (ref i31) (local.get $1)))
                                              )
                                            )
                                            (else
                                              (struct.get $integer 0 (ref.cast (ref $integer) (local.get $1)))
                                            )
                                          )
                                        )
                                        (i64.const 1)
                                      )
                                    )
                                    (local.get $8)
                                  )
                                  (i64.xor (local.get $7) (i64.const 1))
                                )
                                (i64.const 0)
                              )
                            )
                            (br_if $block
                              (i32.or
                                (ref.is_null (local.tee $1 (array.get $vector (local.get $0) (i32.const 1))))
                                (ref.eq (local.get $1) (global.get $uninitialized))
                              )
                            )
                            (br_if $block
                              (i32.or
                                (ref.is_null (local.tee $10 (array.get $vector (local.get $0) (i32.const 2))))
                                (ref.eq (local.get $10) (global.get $uninitialized))
                              )
                            )
                            (br_if $block3
                              (i64.lt_s
                                (i64.and
                                  (i64.xor
                                    (local.tee $8
                                      (i64.add
                                        (local.tee $9
                                          (if
                                            (result i64)
                                            (ref.test (ref i31) (local.get $10))
                                            (then
                                              (i64.extend_i32_s
                                                (i31.get_s (ref.cast (ref i31) (local.get $10)))
                                              )
                                            )
                                            (else
                                              (struct.get $integer 0
                                                (ref.cast (ref $integer) (local.get $10))
                                              )
                                            )
                                          )
                                        )
                                        (i64.const 1)
                                      )
                                    )
                                    (local.get $9)
                                  )
                                  (i64.xor (local.get $8) (i64.const 1))
                                )
                                (i64.const 0)
                              )
                            )
                            (br_if $block
                              (ref.eq
                                (local.tee $16
                                  (struct.get $cell 0
                                    (ref.cast (ref $cell) (array.get $vector (local.get $0) (i32.const 3)))
                                  )
                                )
                                (global.get $uninitialized)
                              )
                            )
                            (local.set $14 (struct.get $closure 1 (ref.cast (ref $closure) (local.get $16))))
                            (local.set $9
                              (if
                                (result i64)
                                (ref.test (ref i31) (local.get $1))
                                (then (i64.extend_i32_s (i31.get_s (ref.cast (ref i31) (local.get $1)))))
                                (else (struct.get $integer 0 (ref.cast (ref $integer) (local.get $1))))
                              )
                            )
                            (local.set $1
                              (block $block5
                                (result eqref)
                                (br_if $block
                                  (i32.or
                                    (ref.is_null
                                      (local.tee $1 (array.get $vector (local.get $14) (i32.const 1)))
                                    )
                                    (ref.eq (local.get $1) (global.get $uninitialized))
                                  )
                                )
                                (if
                                  (ref.test (ref $values) (local.get $1))
                                  (then
                                    (br_if $block4
                                      (i32.ne
                                        (array.len
                                          (local.tee $13
                                            (struct.get $values 0 (ref.cast (ref $values) (local.get $1)))
                                          )
                                        )
                                        (i32.const 1)
                                      )
                                    )
                                    (br $block5 (array.get $vector (local.get $13) (i32.const 0)))
                                  )
                                )
                                (local.get $1)
                              )
                            )
                            (local.set $1
                              (block $block6
                                (result eqref)
                                (br_if $block (ref.is_null (local.tee $12 (global.get $g137))))
                                (drop (struct.get $closure 1 (local.get $12)))
                                (local.set $1
                                  (call $abi_take
                                    (call $snail:read-char
                                      (local.tee $3
                                        (call $abi_root (array.new_fixed $vector 1 (local.get $1)))
                                      )
                                    )
                                  )
                                )
                                (if (i32.ge_u (local.get $3) (global.get $abi_used)) (then (unreachable)))
                                (if
                                  (i32.ne
                                    (array.get $text (global.get $abi_links) (local.get $3))
                                    (i32.const -1)
                                  )
                                  (then (unreachable))
                                )
                                (drop (table.get $abi_roots (local.get $3)))
                                (table.set $abi_roots (local.get $3) (ref.null none))
                                (array.set $text
                                  (global.get $abi_links)
                                  (local.get $3)
                                  (global.get $abi_free)
                                )
                                (global.set $abi_free (local.get $3))
                                (global.set $abi_live (i32.sub (global.get $abi_live) (i32.const 1)))
                                (if
                                  (ref.test (ref $values) (local.get $1))
                                  (then
                                    (br_if $block4
                                      (i32.ne
                                        (array.len
                                          (local.tee $13
                                            (struct.get $values 0 (ref.cast (ref $values) (local.get $1)))
                                          )
                                        )
                                        (i32.const 1)
                                      )
                                    )
                                    (br $block6 (array.get $vector (local.get $13) (i32.const 0)))
                                  )
                                )
                                (local.get $1)
                              )
                            )
                            (return_call $function420
                              (array.new_fixed $vector 5
                                (if
                                  (result (ref eq))
                                  (i32.and
                                    (i64.le_s (local.get $7) (i64.const 1073741823))
                                    (i64.ge_s (local.get $7) (i64.const -1073741824))
                                  )
                                  (then (ref.i31 (i32.wrap_i64 (local.get $7))))
                                  (else (struct.new $integer (local.get $7)))
                                )
                                (if
                                  (result (ref eq))
                                  (i32.and
                                    (i64.le_s (local.get $9) (i64.const 1073741823))
                                    (i64.ge_s (local.get $9) (i64.const -1073741824))
                                  )
                                  (then (ref.i31 (i32.wrap_i64 (local.get $9))))
                                  (else (struct.new $integer (local.get $9)))
                                )
                                (if
                                  (result (ref eq))
                                  (i32.and
                                    (i64.le_s (local.get $8) (i64.const 1073741823))
                                    (i64.ge_s (local.get $8) (i64.const -1073741824))
                                  )
                                  (then (ref.i31 (i32.wrap_i64 (local.get $8))))
                                  (else (struct.new $integer (local.get $8)))
                                )
                                (array.get $vector (local.get $14) (i32.const 0))
                                (global.get $false)
                              )
                              (local.get $1)
                              (local.get $2)
                            )
                          )
                          (else
                            (br_if $block
                              (i32.or
                                (ref.is_null (local.tee $1 (array.get $vector (local.get $0) (i32.const 0))))
                                (ref.eq (local.get $1) (global.get $uninitialized))
                              )
                            )
                            (br_if $block
                              (i32.or
                                (ref.is_null (local.tee $10 (array.get $vector (local.get $0) (i32.const 4))))
                                (ref.eq (local.get $10) (global.get $uninitialized))
                              )
                            )
                            (local.set $10
                              (if
                                (result eqref)
                                (ref.eq (local.get $10) (global.get $false))
                                (then
                                  (br_if $block
                                    (i32.or
                                      (ref.is_null
                                        (local.tee $10 (array.get $vector (local.get $0) (i32.const 1)))
                                      )
                                      (ref.eq (local.get $10) (global.get $uninitialized))
                                    )
                                  )
                                  (br_if $block3
                                    (i64.lt_s
                                      (i64.and
                                        (i64.xor
                                          (local.tee $7
                                            (i64.add
                                              (local.tee $8
                                                (if
                                                  (result i64)
                                                  (ref.test (ref i31) (local.get $10))
                                                  (then
                                                    (i64.extend_i32_s
                                                      (i31.get_s (ref.cast (ref i31) (local.get $10)))
                                                    )
                                                  )
                                                  (else
                                                    (struct.get $integer 0
                                                      (ref.cast (ref $integer) (local.get $10))
                                                    )
                                                  )
                                                )
                                              )
                                              (i64.const 1)
                                            )
                                          )
                                          (local.get $8)
                                        )
                                        (i64.xor (local.get $7) (i64.const 1))
                                      )
                                      (i64.const 0)
                                    )
                                  )
                                  (if
                                    (result (ref eq))
                                    (i32.and
                                      (i64.le_s (local.get $7) (i64.const 1073741823))
                                      (i64.ge_s (local.get $7) (i64.const -1073741824))
                                    )
                                    (then (ref.i31 (i32.wrap_i64 (local.get $7))))
                                    (else (struct.new $integer (local.get $7)))
                                  )
                                )
                                (else
                                  (br_if $block
                                    (i32.or
                                      (ref.is_null
                                        (local.tee $10 (array.get $vector (local.get $0) (i32.const 1)))
                                      )
                                      (ref.eq (local.get $10) (global.get $uninitialized))
                                    )
                                  )
                                  (local.get $10)
                                )
                              )
                            )
                            (br_if $block
                              (i32.or
                                (ref.is_null (local.tee $11 (array.get $vector (local.get $0) (i32.const 2))))
                                (ref.eq (local.get $11) (global.get $uninitialized))
                              )
                            )
                            (br_if $block3
                              (i64.lt_s
                                (i64.and
                                  (i64.xor
                                    (local.tee $7
                                      (i64.add
                                        (local.tee $8
                                          (if
                                            (result i64)
                                            (ref.test (ref i31) (local.get $11))
                                            (then
                                              (i64.extend_i32_s
                                                (i31.get_s (ref.cast (ref i31) (local.get $11)))
                                              )
                                            )
                                            (else
                                              (struct.get $integer 0
                                                (ref.cast (ref $integer) (local.get $11))
                                              )
                                            )
                                          )
                                        )
                                        (i64.const 1)
                                      )
                                    )
                                    (local.get $8)
                                  )
                                  (i64.xor (local.get $7) (i64.const 1))
                                )
                                (i64.const 0)
                              )
                            )
                            (i32.const 1)
                          )
                        )
                      )
                    )
                  )
                )
              )
              (br_if $block
                (ref.eq
                  (local.tee $16
                    (struct.get $cell 0
                      (ref.cast (ref $cell) (array.get $vector (local.get $0) (i32.const 3)))
                    )
                  )
                  (global.get $uninitialized)
                )
              )
              (local.set $14 (struct.get $closure 1 (ref.cast (ref $closure) (local.get $16))))
              (local.set $8
                (if
                  (result i64)
                  (ref.test (ref i31) (local.get $1))
                  (then (i64.extend_i32_s (i31.get_s (ref.cast (ref i31) (local.get $1)))))
                  (else (struct.get $integer 0 (ref.cast (ref $integer) (local.get $1))))
                )
              )
              (local.set $9
                (if
                  (result i64)
                  (ref.test (ref i31) (local.get $10))
                  (then (i64.extend_i32_s (i31.get_s (ref.cast (ref i31) (local.get $10)))))
                  (else (struct.get $integer 0 (ref.cast (ref $integer) (local.get $10))))
                )
              )
              (local.set $1
                (block $block7
                  (result eqref)
                  (br_if $block
                    (i32.or
                      (ref.is_null (local.tee $1 (array.get $vector (local.get $14) (i32.const 1))))
                      (ref.eq (local.get $1) (global.get $uninitialized))
                    )
                  )
                  (if
                    (ref.test (ref $values) (local.get $1))
                    (then
                      (br_if $block4
                        (i32.ne
                          (array.len
                            (local.tee $13 (struct.get $values 0 (ref.cast (ref $values) (local.get $1))))
                          )
                          (i32.const 1)
                        )
                      )
                      (br $block7 (array.get $vector (local.get $13) (i32.const 0)))
                    )
                  )
                  (local.get $1)
                )
              )
              (local.set $1
                (block $block8
                  (result eqref)
                  (br_if $block (ref.is_null (local.tee $12 (global.get $g137))))
                  (drop (struct.get $closure 1 (local.get $12)))
                  (local.set $1
                    (call $abi_take
                      (call $snail:read-char
                        (local.tee $3 (call $abi_root (array.new_fixed $vector 1 (local.get $1))))
                      )
                    )
                  )
                  (if (i32.ge_u (local.get $3) (global.get $abi_used)) (then (unreachable)))
                  (if
                    (i32.ne (array.get $text (global.get $abi_links) (local.get $3)) (i32.const -1))
                    (then (unreachable))
                  )
                  (drop (table.get $abi_roots (local.get $3)))
                  (table.set $abi_roots (local.get $3) (ref.null none))
                  (array.set $text (global.get $abi_links) (local.get $3) (global.get $abi_free))
                  (global.set $abi_free (local.get $3))
                  (global.set $abi_live (i32.sub (global.get $abi_live) (i32.const 1)))
                  (if
                    (ref.test (ref $values) (local.get $1))
                    (then
                      (br_if $block4
                        (i32.ne
                          (array.len
                            (local.tee $13 (struct.get $values 0 (ref.cast (ref $values) (local.get $1))))
                          )
                          (i32.const 1)
                        )
                      )
                      (br $block8 (array.get $vector (local.get $13) (i32.const 0)))
                    )
                  )
                  (local.get $1)
                )
              )
              (return_call $function420
                (array.new_fixed $vector 5
                  (if
                    (result (ref eq))
                    (i32.and
                      (i64.le_s (local.get $8) (i64.const 1073741823))
                      (i64.ge_s (local.get $8) (i64.const -1073741824))
                    )
                    (then (ref.i31 (i32.wrap_i64 (local.get $8))))
                    (else (struct.new $integer (local.get $8)))
                  )
                  (if
                    (result (ref eq))
                    (i32.and
                      (i64.le_s (local.get $9) (i64.const 1073741823))
                      (i64.ge_s (local.get $9) (i64.const -1073741824))
                    )
                    (then (ref.i31 (i32.wrap_i64 (local.get $9))))
                    (else (struct.new $integer (local.get $9)))
                  )
                  (if
                    (result (ref eq))
                    (i32.and
                      (i64.le_s (local.get $7) (i64.const 1073741823))
                      (i64.ge_s (local.get $7) (i64.const -1073741824))
                    )
                    (then (ref.i31 (i32.wrap_i64 (local.get $7))))
                    (else (struct.new $integer (local.get $7)))
                  )
                  (array.get $vector (local.get $14) (i32.const 0))
                  (select (result (ref $atom)) (global.get $true) (global.get $false) (local.get $4))
                )
                (local.get $1)
                (local.get $2)
              )
            )
            (global.set $error_code (i32.const 2))
            (local.set $3 (i32.load (i32.const 1062296)))
            (br $block1 (i32.load (i32.const 1062336)))
          )
          (global.set $error_code (i32.const 6))
          (local.set $3 (i32.load (i32.const 1062312)))
          (br $block1 (i32.load (i32.const 1062352)))
        )
        (global.set $error_code (i32.const 5))
        (local.set $3 (i32.load (i32.const 1062308)))
        (br $block1 (i32.load (i32.const 1062348)))
      )
      (global.set $error_code (i32.const 8))
      (local.set $3 (i32.load (i32.const 1062320)))
      (i32.load (i32.const 1062360))
    )
  )
  (global.set $__stack_pointer (local.tee $4 (i32.sub (global.get $__stack_pointer) (i32.const 32))))
  (call $_RNvMNtCsi9YzqDQQz2q_5alloc6stringNtB2_6String15from_utf8_lossy
    (local.tee $6 (i32.add (local.get $4) (i32.const 12)))
    (local.get $5)
    (local.get $3)
  )
  (i64.store offset=24 (local.get $4) (i64.or (i64.extend_i32_u (local.get $6)) (i64.const 103079215104)))
  (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio7__eprint (i32.add (local.get $4) (i32.const 24)))
  (local.set $3 (i32.load offset=16 (local.get $4)))
  (if (i32.gt_s (i32.load offset=12 (local.get $4)) (i32.const 0)) (then (call $dlfree (local.get $3))))
  (call $_RNvNtCset5xJoy1xWQ_3std2rt7cleanup)
  (call $__imported_wasi_snapshot_preview1_proc_exit (i32.const 1))
  (unreachable)
)
