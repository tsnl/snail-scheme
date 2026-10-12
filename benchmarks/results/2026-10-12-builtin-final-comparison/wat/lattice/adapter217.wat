(func $adapter217
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
  (local $8 eqref)
  (local $9 eqref)
  (local $10 (ref null $closure))
  (local $scratch eqref)
  (local $scratch_12 eqref)
  (local $scratch_13 eqref)
  (local.set $5
    (block $block
      (result i32)
      (if
        (i32.or
          (i32.ne (local.tee $3 (array.len (local.get $1))) (i32.const 2))
          (i32.lt_u (local.get $3) (i32.const 2))
        )
        (then
          (global.set $error_code (i32.const 4))
          (local.set $4 (i32.load (i32.const 1062304)))
          (br $block (i32.load (i32.const 1062344)))
        )
      )
      (block $block2
        (block $block1
          (return
            (block $block19
              (result eqref)
              (local.set $0 (array.get $vector (local.get $1) (i32.const 1)))
              (block $block4
                (br_if $block4
                  (i32.or
                    (ref.is_null
                      (local.tee $8
                        (block $block3
                          (result eqref)
                          (br_if $block1
                            (i32.or
                              (ref.is_null (local.tee $7 (array.get $vector (local.get $1) (i32.const 0))))
                              (ref.eq (local.get $7) (global.get $uninitialized))
                            )
                          )
                          (if
                            (ref.test (ref $values) (local.get $7))
                            (then
                              (br_if $block2
                                (i32.ne
                                  (array.len
                                    (local.tee $1
                                      (struct.get $values 0 (ref.cast (ref $values) (local.get $7)))
                                    )
                                  )
                                  (i32.const 1)
                                )
                              )
                              (br $block3 (array.get $vector (local.get $1) (i32.const 0)))
                            )
                          )
                          (local.get $7)
                        )
                      )
                    )
                    (ref.eq (local.get $8) (global.get $uninitialized))
                  )
                )
                (br_if $block4 (ref.is_null (local.tee $10 (global.get $g224))))
                (drop (ref.as_non_null (local.get $10)))
                (block $block5
                  (if
                    (ref.eq
                      (block $block6
                        (result eqref)
                        (if
                          (ref.test
                            (ref $values)
                            (local.tee $9
                              (call $function31 (local.get $8) (global.get $literal30) (ref.null none))
                            )
                          )
                          (then
                            (br_if $block5
                              (i32.ne
                                (array.len
                                  (local.tee $1
                                    (struct.get $values 0 (ref.cast (ref $values) (local.get $9)))
                                  )
                                )
                                (i32.const 1)
                              )
                            )
                            (br $block6 (array.get $vector (local.get $1) (i32.const 0)))
                          )
                        )
                        (local.get $9)
                      )
                      (global.get $false)
                    )
                    (then
                      (br_if $block4
                        (local.tee $3
                          (i32.or
                            (ref.is_null (local.get $8))
                            (ref.eq (local.get $8) (global.get $uninitialized))
                          )
                        )
                      )
                      (br $block19
                        (block $block10
                          (result eqref)
                          (br_if $block4 (local.get $3))
                          (br_if $block4 (ref.is_null (local.tee $10 (global.get $g224))))
                          (drop (ref.as_non_null (local.get $10)))
                          (block $block7
                            (if
                              (ref.eq
                                (block $block8
                                  (result eqref)
                                  (if
                                    (ref.test
                                      (ref $values)
                                      (local.tee $9
                                        (call $function31
                                          (local.get $8)
                                          (global.get $literal35)
                                          (ref.null none)
                                        )
                                      )
                                    )
                                    (then
                                      (br_if $block7
                                        (i32.ne
                                          (array.len
                                            (local.tee $1
                                              (struct.get $values 0 (ref.cast (ref $values) (local.get $9)))
                                            )
                                          )
                                          (i32.const 1)
                                        )
                                      )
                                      (br $block8 (array.get $vector (local.get $1) (i32.const 0)))
                                    )
                                  )
                                  (local.get $9)
                                )
                                (global.get $false)
                              )
                              (then
                                (br_if $block4
                                  (i32.or
                                    (ref.is_null (local.get $8))
                                    (ref.eq (local.get $8) (global.get $uninitialized))
                                  )
                                )
                                (local.set $0
                                  (block $block9
                                    (result eqref)
                                    (br_if $block4
                                      (i32.or
                                        (ref.is_null (local.get $7))
                                        (ref.eq (local.get $7) (global.get $uninitialized))
                                      )
                                    )
                                    (if
                                      (ref.test (ref $values) (local.get $7))
                                      (then
                                        (br_if $block7
                                          (i32.ne
                                            (array.len
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $7)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block9 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $7)
                                  )
                                )
                                (br_if $block4 (ref.is_null (local.tee $10 (global.get $g122))))
                                (drop (struct.get $closure 1 (local.get $10)))
                                (br $block10
                                  (block
                                    (result eqref)
                                    (local.set $scratch
                                      (call $abi_take
                                        (call $snail:error
                                          (local.tee $3
                                            (call $abi_root
                                              (array.new_fixed $vector 3
                                                (global.get $literal33)
                                                (global.get $literal39)
                                                (local.get $0)
                                              )
                                            )
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
                                    (local.get $scratch)
                                  )
                                )
                              )
                              (else
                                (br $block19
                                  (block $block18
                                    (result eqref)
                                    (br_if $block4
                                      (i32.or
                                        (ref.is_null
                                          (local.tee $7
                                            (block $block11
                                              (result eqref)
                                              (br_if $block4
                                                (i32.or
                                                  (ref.is_null (local.get $0))
                                                  (ref.eq (local.get $0) (global.get $uninitialized))
                                                )
                                              )
                                              (if
                                                (ref.test (ref $values) (local.get $0))
                                                (then
                                                  (br_if $block7
                                                    (i32.ne
                                                      (array.len
                                                        (local.tee $1
                                                          (struct.get $values 0
                                                            (ref.cast (ref $values) (local.get $0))
                                                          )
                                                        )
                                                      )
                                                      (i32.const 1)
                                                    )
                                                  )
                                                  (br $block11
                                                    (array.get $vector (local.get $1) (i32.const 0))
                                                  )
                                                )
                                              )
                                              (local.get $0)
                                            )
                                          )
                                        )
                                        (ref.eq (local.get $7) (global.get $uninitialized))
                                      )
                                    )
                                    (br_if $block4 (ref.is_null (local.tee $10 (global.get $g224))))
                                    (drop (ref.as_non_null (local.get $10)))
                                    (block $block12
                                      (br $block18
                                        (if
                                          (result (ref $atom))
                                          (ref.eq
                                            (block $block13
                                              (result eqref)
                                              (if
                                                (ref.test
                                                  (ref $values)
                                                  (local.tee $8
                                                    (call $function31
                                                      (local.get $7)
                                                      (global.get $literal36)
                                                      (ref.null none)
                                                    )
                                                  )
                                                )
                                                (then
                                                  (br_if $block12
                                                    (i32.ne
                                                      (array.len
                                                        (local.tee $1
                                                          (struct.get $values 0
                                                            (ref.cast (ref $values) (local.get $8))
                                                          )
                                                        )
                                                      )
                                                      (i32.const 1)
                                                    )
                                                  )
                                                  (br $block13
                                                    (array.get $vector (local.get $1) (i32.const 0))
                                                  )
                                                )
                                              )
                                              (local.get $8)
                                            )
                                            (global.get $false)
                                          )
                                          (then
                                            (br_if $block4
                                              (local.tee $3
                                                (i32.or
                                                  (ref.is_null (local.get $7))
                                                  (ref.eq (local.get $7) (global.get $uninitialized))
                                                )
                                              )
                                            )
                                            (br $block18
                                              (block $block17
                                                (result eqref)
                                                (br_if $block4 (local.get $3))
                                                (br_if $block4
                                                  (ref.is_null (local.tee $10 (global.get $g224)))
                                                )
                                                (drop (ref.as_non_null (local.get $10)))
                                                (block $block14
                                                  (br $block17
                                                    (if
                                                      (result (ref $atom))
                                                      (ref.eq
                                                        (block $block15
                                                          (result eqref)
                                                          (if
                                                            (ref.test
                                                              (ref $values)
                                                              (local.tee $8
                                                                (call $function31
                                                                  (local.get $7)
                                                                  (global.get $literal37)
                                                                  (ref.null none)
                                                                )
                                                              )
                                                            )
                                                            (then
                                                              (br_if $block14
                                                                (i32.ne
                                                                  (array.len
                                                                    (local.tee $1
                                                                      (struct.get $values 0
                                                                        (ref.cast
                                                                          (ref $values)
                                                                          (local.get $8)
                                                                        )
                                                                      )
                                                                    )
                                                                  )
                                                                  (i32.const 1)
                                                                )
                                                              )
                                                              (br $block15
                                                                (array.get $vector
                                                                  (local.get $1)
                                                                  (i32.const 0)
                                                                )
                                                              )
                                                            )
                                                          )
                                                          (local.get $8)
                                                        )
                                                        (global.get $false)
                                                      )
                                                      (then
                                                        (br_if $block4
                                                          (i32.or
                                                            (ref.is_null (local.get $7))
                                                            (ref.eq
                                                              (local.get $7)
                                                              (global.get $uninitialized)
                                                            )
                                                          )
                                                        )
                                                        (local.set $0
                                                          (block $block16
                                                            (result eqref)
                                                            (br_if $block4
                                                              (i32.or
                                                                (ref.is_null (local.get $0))
                                                                (ref.eq
                                                                  (local.get $0)
                                                                  (global.get $uninitialized)
                                                                )
                                                              )
                                                            )
                                                            (if
                                                              (ref.test (ref $values) (local.get $0))
                                                              (then
                                                                (br_if $block14
                                                                  (i32.ne
                                                                    (array.len
                                                                      (local.tee $1
                                                                        (struct.get $values 0
                                                                          (ref.cast
                                                                            (ref $values)
                                                                            (local.get $0)
                                                                          )
                                                                        )
                                                                      )
                                                                    )
                                                                    (i32.const 1)
                                                                  )
                                                                )
                                                                (br $block16
                                                                  (array.get $vector
                                                                    (local.get $1)
                                                                    (i32.const 0)
                                                                  )
                                                                )
                                                              )
                                                            )
                                                            (local.get $0)
                                                          )
                                                        )
                                                        (br_if $block4
                                                          (ref.is_null (local.tee $10 (global.get $g122)))
                                                        )
                                                        (drop (struct.get $closure 1 (local.get $10)))
                                                        (br $block17
                                                          (block
                                                            (result eqref)
                                                            (local.set $scratch_12
                                                              (call $abi_take
                                                                (call $snail:error
                                                                  (local.tee $3
                                                                    (call $abi_root
                                                                      (array.new_fixed $vector 3
                                                                        (global.get $literal33)
                                                                        (global.get $literal38)
                                                                        (local.get $0)
                                                                      )
                                                                    )
                                                                  )
                                                                )
                                                              )
                                                            )
                                                            (if
                                                              (i32.ge_u (local.get $3) (global.get $abi_used))
                                                              (then (unreachable))
                                                            )
                                                            (if
                                                              (i32.ne
                                                                (array.get $text
                                                                  (global.get $abi_links)
                                                                  (local.get $3)
                                                                )
                                                                (i32.const -1)
                                                              )
                                                              (then (unreachable))
                                                            )
                                                            (drop (table.get $abi_roots (local.get $3)))
                                                            (table.set $abi_roots
                                                              (local.get $3)
                                                              (ref.null none)
                                                            )
                                                            (array.set $text
                                                              (global.get $abi_links)
                                                              (local.get $3)
                                                              (global.get $abi_free)
                                                            )
                                                            (global.set $abi_free (local.get $3))
                                                            (global.set $abi_live
                                                              (i32.sub (global.get $abi_live) (i32.const 1))
                                                            )
                                                            (local.get $scratch_12)
                                                          )
                                                        )
                                                      )
                                                      (else (global.get $literal14))
                                                    )
                                                  )
                                                )
                                                (br $block12)
                                              )
                                            )
                                          )
                                          (else (global.get $literal19))
                                        )
                                      )
                                    )
                                    (br $block5)
                                  )
                                )
                              )
                            )
                            (unreachable)
                          )
                          (br $block5)
                        )
                      )
                    )
                    (else
                      (br $block19
                        (block $block27
                          (result eqref)
                          (br_if $block4
                            (i32.or
                              (ref.is_null
                                (local.tee $7
                                  (block $block20
                                    (result eqref)
                                    (br_if $block4
                                      (i32.or
                                        (ref.is_null (local.get $0))
                                        (ref.eq (local.get $0) (global.get $uninitialized))
                                      )
                                    )
                                    (if
                                      (ref.test (ref $values) (local.get $0))
                                      (then
                                        (br_if $block5
                                          (i32.ne
                                            (array.len
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block20 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $0)
                                  )
                                )
                              )
                              (ref.eq (local.get $7) (global.get $uninitialized))
                            )
                          )
                          (br_if $block4 (ref.is_null (local.tee $10 (global.get $g224))))
                          (drop (ref.as_non_null (local.get $10)))
                          (block $block21
                            (br $block27
                              (if
                                (result (ref $atom))
                                (ref.eq
                                  (block $block22
                                    (result eqref)
                                    (if
                                      (ref.test
                                        (ref $values)
                                        (local.tee $8
                                          (call $function31
                                            (local.get $7)
                                            (global.get $literal31)
                                            (ref.null none)
                                          )
                                        )
                                      )
                                      (then
                                        (br_if $block21
                                          (i32.ne
                                            (array.len
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $8)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block22 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $8)
                                  )
                                  (global.get $false)
                                )
                                (then
                                  (br_if $block4
                                    (local.tee $3
                                      (i32.or
                                        (ref.is_null (local.get $7))
                                        (ref.eq (local.get $7) (global.get $uninitialized))
                                      )
                                    )
                                  )
                                  (br $block27
                                    (block $block26
                                      (result eqref)
                                      (br_if $block4 (local.get $3))
                                      (br_if $block4 (ref.is_null (local.tee $10 (global.get $g224))))
                                      (drop (ref.as_non_null (local.get $10)))
                                      (block $block23
                                        (br $block26
                                          (if
                                            (result (ref $atom))
                                            (ref.eq
                                              (block $block24
                                                (result eqref)
                                                (if
                                                  (ref.test
                                                    (ref $values)
                                                    (local.tee $8
                                                      (call $function31
                                                        (local.get $7)
                                                        (global.get $literal32)
                                                        (ref.null none)
                                                      )
                                                    )
                                                  )
                                                  (then
                                                    (br_if $block23
                                                      (i32.ne
                                                        (array.len
                                                          (local.tee $1
                                                            (struct.get $values 0
                                                              (ref.cast (ref $values) (local.get $8))
                                                            )
                                                          )
                                                        )
                                                        (i32.const 1)
                                                      )
                                                    )
                                                    (br $block24
                                                      (array.get $vector (local.get $1) (i32.const 0))
                                                    )
                                                  )
                                                )
                                                (local.get $8)
                                              )
                                              (global.get $false)
                                            )
                                            (then
                                              (br_if $block4
                                                (i32.or
                                                  (ref.is_null (local.get $7))
                                                  (ref.eq (local.get $7) (global.get $uninitialized))
                                                )
                                              )
                                              (local.set $0
                                                (block $block25
                                                  (result eqref)
                                                  (br_if $block4
                                                    (i32.or
                                                      (ref.is_null (local.get $0))
                                                      (ref.eq (local.get $0) (global.get $uninitialized))
                                                    )
                                                  )
                                                  (if
                                                    (ref.test (ref $values) (local.get $0))
                                                    (then
                                                      (br_if $block23
                                                        (i32.ne
                                                          (array.len
                                                            (local.tee $1
                                                              (struct.get $values 0
                                                                (ref.cast (ref $values) (local.get $0))
                                                              )
                                                            )
                                                          )
                                                          (i32.const 1)
                                                        )
                                                      )
                                                      (br $block25
                                                        (array.get $vector (local.get $1) (i32.const 0))
                                                      )
                                                    )
                                                  )
                                                  (local.get $0)
                                                )
                                              )
                                              (br_if $block4 (ref.is_null (local.tee $10 (global.get $g122))))
                                              (drop (struct.get $closure 1 (local.get $10)))
                                              (br $block26
                                                (block
                                                  (result eqref)
                                                  (local.set $scratch_13
                                                    (call $abi_take
                                                      (call $snail:error
                                                        (local.tee $3
                                                          (call $abi_root
                                                            (array.new_fixed $vector 3
                                                              (global.get $literal33)
                                                              (global.get $literal34)
                                                              (local.get $0)
                                                            )
                                                          )
                                                        )
                                                      )
                                                    )
                                                  )
                                                  (if
                                                    (i32.ge_u (local.get $3) (global.get $abi_used))
                                                    (then (unreachable))
                                                  )
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
                                                  (global.set $abi_live
                                                    (i32.sub (global.get $abi_live) (i32.const 1))
                                                  )
                                                  (local.get $scratch_13)
                                                )
                                              )
                                            )
                                            (else (global.get $literal17))
                                          )
                                        )
                                      )
                                      (br $block21)
                                    )
                                  )
                                )
                                (else (global.get $literal14))
                              )
                            )
                          )
                          (br $block5)
                        )
                      )
                    )
                  )
                  (unreachable)
                )
                (br $block2)
              )
              (br $block1)
            )
          )
        )
        (global.set $error_code (i32.const 6))
        (local.set $4 (i32.load (i32.const 1062312)))
        (br $block (i32.load (i32.const 1062352)))
      )
      (global.set $error_code (i32.const 5))
      (local.set $4 (i32.load (i32.const 1062308)))
      (i32.load (i32.const 1062348))
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
