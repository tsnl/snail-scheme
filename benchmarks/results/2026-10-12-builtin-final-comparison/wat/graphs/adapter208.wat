(func $adapter208
  (type $call)
  (param $0 eqref)
  (param $1 (ref $vector))
  (param $2 nullref)
  (result eqref)
  (local $3 i32)
  (local $4 i32)
  (local $5 i32)
  (local $6 i32)
  (local $7 i64)
  (local $8 eqref)
  (local $9 eqref)
  (local $10 eqref)
  (local $11 eqref)
  (local $12 eqref)
  (local $13 eqref)
  (local $14 eqref)
  (local $15 eqref)
  (local $16 eqref)
  (local $17 eqref)
  (local $18 eqref)
  (local $19 (ref null $closure))
  (local $20 (ref $closure))
  (local $21 (ref null $vector))
  (local $22 (ref $cell))
  (local $23 (ref i31))
  (local $24 (ref struct))
  (local $scratch eqref)
  (local.set $5
    (block $block
      (result i32)
      (if
        (i32.or
          (i32.ne (local.tee $3 (array.len (local.get $1))) (i32.const 5))
          (i32.lt_u (local.get $3) (i32.const 5))
        )
        (then
          (global.set $error_code (i32.const 4))
          (local.set $3 (i32.load (i32.const 1062304)))
          (br $block (i32.load (i32.const 1062344)))
        )
      )
      (local.set $10 (array.get $vector (local.get $1) (i32.const 0)))
      (local.set $8 (array.get $vector (local.get $1) (i32.const 1)))
      (local.set $13 (array.get $vector (local.get $1) (i32.const 2)))
      (local.set $14 (array.get $vector (local.get $1) (i32.const 3)))
      (local.set $15 (array.get $vector (local.get $1) (i32.const 4)))
      (block $block1
        (block $block2
          (local.set $0
            (block $block3
              (result eqref)
              (br_if $block1
                (i32.or
                  (ref.is_null
                    (local.tee $0
                      (array.get $vector
                        (local.tee $21 (ref.cast (ref $vector) (local.get $0)))
                        (i32.const 1)
                      )
                    )
                  )
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
          (br_if $block1
            (i32.or
              (ref.is_null (local.tee $17 (array.get $vector (local.get $21) (i32.const 0))))
              (ref.eq (local.get $17) (global.get $uninitialized))
            )
          )
          (local.set $9
            (block $block4
              (result eqref)
              (br_if $block1
                (i32.or (ref.is_null (local.get $8)) (ref.eq (local.get $8) (global.get $uninitialized)))
              )
              (if
                (ref.test (ref $values) (local.get $8))
                (then
                  (br_if $block2
                    (i32.ne
                      (array.len
                        (local.tee $1 (struct.get $values 0 (ref.cast (ref $values) (local.get $8))))
                      )
                      (i32.const 1)
                    )
                  )
                  (br $block4 (array.get $vector (local.get $1) (i32.const 0)))
                )
              )
              (local.get $8)
            )
          )
          (local.set $11
            (block $block5
              (result eqref)
              (br_if $block1
                (i32.or (ref.is_null (local.get $10)) (ref.eq (local.get $10) (global.get $uninitialized)))
              )
              (if
                (ref.test (ref $values) (local.get $10))
                (then
                  (br_if $block2
                    (i32.ne
                      (array.len
                        (local.tee $1 (struct.get $values 0 (ref.cast (ref $values) (local.get $10))))
                      )
                      (i32.const 1)
                    )
                  )
                  (br $block5 (array.get $vector (local.get $1) (i32.const 0)))
                )
              )
              (local.get $10)
            )
          )
          (br_if $block1 (ref.is_null (local.tee $19 (global.get $g293))))
          (drop (ref.as_non_null (local.get $19)))
          (local.set $16
            (block $block6
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
                  (br $block6 (array.get $vector (local.get $1) (i32.const 0)))
                )
              )
              (local.get $0)
            )
          )
          (local.set $12
            (block $block7
              (result eqref)
              (br_if $block1
                (i32.or (ref.is_null (local.get $9)) (ref.eq (local.get $9) (global.get $uninitialized)))
              )
              (if
                (ref.test (ref $values) (local.get $9))
                (then
                  (br_if $block2
                    (i32.ne
                      (array.len
                        (local.tee $1 (struct.get $values 0 (ref.cast (ref $values) (local.get $9))))
                      )
                      (i32.const 1)
                    )
                  )
                  (br $block7 (array.get $vector (local.get $1) (i32.const 0)))
                )
              )
              (local.get $9)
            )
          )
          (block $block9
            (block $block8
              (local.set $16
                (block $block10
                  (result eqref)
                  (if
                    (ref.test
                      (ref $values)
                      (local.tee $12
                        (array.get $vector
                          (ref.cast (ref $vector) (local.get $16))
                          (block
                            (result i32)
                            (br_if $block9
                              (i64.gt_u
                                (local.tee $7
                                  (if
                                    (result i64)
                                    (ref.test (ref i31) (local.get $12))
                                    (then (i64.extend_i32_s (i31.get_s (ref.cast (ref i31) (local.get $12)))))
                                    (else
                                      (if
                                        (result i64)
                                        (ref.test (ref $integer) (local.get $12))
                                        (then
                                          (struct.get $integer 0 (ref.cast (ref $integer) (local.get $12)))
                                        )
                                        (else (br $block8))
                                      )
                                    )
                                  )
                                )
                                (i64.const 2147483647)
                              )
                            )
                            (i32.wrap_i64 (local.get $7))
                          )
                        )
                      )
                    )
                    (then
                      (br_if $block2
                        (i32.ne
                          (array.len
                            (local.tee $1 (struct.get $values 0 (ref.cast (ref $values) (local.get $12))))
                          )
                          (i32.const 1)
                        )
                      )
                      (br $block10 (array.get $vector (local.get $1) (i32.const 0)))
                    )
                  )
                  (local.get $12)
                )
              )
              (local.set $18
                (block $block11
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
                      (br $block11 (array.get $vector (local.get $1) (i32.const 0)))
                    )
                  )
                  (local.get $0)
                )
              )
              (local.set $12
                (block $block12
                  (result eqref)
                  (br_if $block1
                    (i32.or
                      (ref.is_null (local.get $11))
                      (ref.eq (local.get $11) (global.get $uninitialized))
                    )
                  )
                  (if
                    (ref.test (ref $values) (local.get $11))
                    (then
                      (br_if $block2
                        (i32.ne
                          (array.len
                            (local.tee $1 (struct.get $values 0 (ref.cast (ref $values) (local.get $11))))
                          )
                          (i32.const 1)
                        )
                      )
                      (br $block12 (array.get $vector (local.get $1) (i32.const 0)))
                    )
                  )
                  (local.get $11)
                )
              )
              (local.set $0
                (block $block14
                  (result eqref)
                  (struct.set $cell 0
                    (local.tee $22 (struct.new $cell (global.get $uninitialized)))
                    (struct.new $closure
                      (ref.func $adapter217)
                      (array.new_fixed $vector 7
                        (local.get $9)
                        (block $block13
                          (result eqref)
                          (if
                            (ref.test
                              (ref $values)
                              (local.tee $9
                                (array.get $vector
                                  (ref.cast (ref $vector) (local.get $18))
                                  (block
                                    (result i32)
                                    (br_if $block9
                                      (i64.gt_u
                                        (local.tee $7
                                          (if
                                            (result i64)
                                            (ref.test (ref i31) (local.get $12))
                                            (then
                                              (i64.extend_i32_s
                                                (i31.get_s (ref.cast (ref i31) (local.get $12)))
                                              )
                                            )
                                            (else
                                              (if
                                                (result i64)
                                                (ref.test (ref $integer) (local.get $12))
                                                (then
                                                  (struct.get $integer 0
                                                    (ref.cast (ref $integer) (local.get $12))
                                                  )
                                                )
                                                (else (br $block8))
                                              )
                                            )
                                          )
                                        )
                                        (i64.const 2147483647)
                                      )
                                    )
                                    (i32.wrap_i64 (local.get $7))
                                  )
                                )
                              )
                            )
                            (then
                              (br_if $block2
                                (i32.ne
                                  (array.len
                                    (local.tee $1
                                      (struct.get $values 0 (ref.cast (ref $values) (local.get $9)))
                                    )
                                  )
                                  (i32.const 1)
                                )
                              )
                              (br $block13 (array.get $vector (local.get $1) (i32.const 0)))
                            )
                          )
                          (local.get $9)
                        )
                        (local.get $0)
                        (local.get $11)
                        (local.get $22)
                        (local.get $16)
                        (local.get $17)
                      )
                    )
                  )
                  (br_if $block1
                    (ref.eq (local.tee $24 (struct.get $cell 0 (local.get $22))) (global.get $uninitialized))
                  )
                  (if
                    (ref.test
                      (ref $values)
                      (local.tee $0
                        (call_ref $call
                          (struct.get $closure 1 (local.tee $20 (ref.cast (ref $closure) (local.get $24))))
                          (array.new_fixed $vector 1 (ref.i31 (i32.const 0)))
                          (ref.null none)
                          (struct.get $closure 0 (local.get $20))
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
                      (br $block14 (array.get $vector (local.get $1) (i32.const 0)))
                    )
                  )
                  (local.get $0)
                )
              )
              (return
                (block $block25
                  (result eqref)
                  (local.set $9 (array.get $vector (local.get $21) (i32.const 0)))
                  (block $block15
                    (br_if $block15
                      (i32.or
                        (ref.is_null (local.get $0))
                        (ref.eq (local.get $0) (global.get $uninitialized))
                      )
                    )
                    (br_if $block15 (ref.is_null (local.tee $19 (global.get $g224))))
                    (drop (ref.as_non_null (local.get $19)))
                    (block $block16
                      (br $block25
                        (if
                          (result (ref $atom))
                          (ref.eq
                            (block $block17
                              (result eqref)
                              (if
                                (ref.test
                                  (ref $values)
                                  (local.tee $11
                                    (call $function31 (local.get $0) (global.get $literal14) (ref.null none))
                                  )
                                )
                                (then
                                  (br_if $block16
                                    (i32.ne
                                      (array.len
                                        (local.tee $1
                                          (struct.get $values 0 (ref.cast (ref $values) (local.get $11)))
                                        )
                                      )
                                      (i32.const 1)
                                    )
                                  )
                                  (br $block17 (array.get $vector (local.get $1) (i32.const 0)))
                                )
                              )
                              (local.get $11)
                            )
                            (global.get $false)
                          )
                          (then
                            (br_if $block15
                              (local.tee $3
                                (i32.or
                                  (ref.is_null (local.get $0))
                                  (ref.eq (local.get $0) (global.get $uninitialized))
                                )
                              )
                            )
                            (br_if $block15 (local.get $3))
                            (br_if $block15 (ref.is_null (local.tee $19 (global.get $g224))))
                            (drop (ref.as_non_null (local.get $19)))
                            (block $block18
                              (if
                                (ref.eq
                                  (block $block19
                                    (result eqref)
                                    (if
                                      (ref.test
                                        (ref $values)
                                        (local.tee $11
                                          (call $function31
                                            (local.get $0)
                                            (global.get $literal16)
                                            (ref.null none)
                                          )
                                        )
                                      )
                                      (then
                                        (br_if $block18
                                          (i32.ne
                                            (array.len
                                              (local.tee $1
                                                (struct.get $values 0
                                                  (ref.cast (ref $values) (local.get $11))
                                                )
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block19 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $11)
                                  )
                                  (global.get $false)
                                )
                                (then
                                  (br_if $block15
                                    (local.tee $3
                                      (i32.or
                                        (ref.is_null (local.get $0))
                                        (ref.eq (local.get $0) (global.get $uninitialized))
                                      )
                                    )
                                  )
                                  (br $block25
                                    (block $block22
                                      (result eqref)
                                      (br_if $block15 (local.get $3))
                                      (br_if $block15 (ref.is_null (local.tee $19 (global.get $g224))))
                                      (drop (ref.as_non_null (local.get $19)))
                                      (block $block20
                                        (if
                                          (ref.eq
                                            (block $block21
                                              (result eqref)
                                              (if
                                                (ref.test
                                                  (ref $values)
                                                  (local.tee $8
                                                    (call $function31
                                                      (local.get $0)
                                                      (global.get $literal18)
                                                      (ref.null none)
                                                    )
                                                  )
                                                )
                                                (then
                                                  (br_if $block20
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
                                                  (br $block21
                                                    (array.get $vector (local.get $1) (i32.const 0))
                                                  )
                                                )
                                              )
                                              (local.get $8)
                                            )
                                            (global.get $false)
                                          )
                                          (then
                                            (br_if $block15
                                              (i32.or
                                                (ref.is_null (local.get $0))
                                                (ref.eq (local.get $0) (global.get $uninitialized))
                                              )
                                            )
                                            (br_if $block15 (ref.is_null (local.tee $19 (global.get $g122))))
                                            (drop (struct.get $closure 1 (local.get $19)))
                                            (br $block22
                                              (block
                                                (result eqref)
                                                (local.set $scratch
                                                  (call $abi_take
                                                    (call $snail:error
                                                      (local.tee $3
                                                        (call $abi_root
                                                          (array.new_fixed $vector 2
                                                            (global.get $false)
                                                            (global.get $literal20)
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
                                                (local.get $scratch)
                                              )
                                            )
                                          )
                                          (else
                                            (local.set $0
                                              (block $block23
                                                (result eqref)
                                                (br_if $block15
                                                  (i32.or
                                                    (ref.is_null (local.get $13))
                                                    (ref.eq (local.get $13) (global.get $uninitialized))
                                                  )
                                                )
                                                (if
                                                  (ref.test (ref $values) (local.get $13))
                                                  (then
                                                    (br_if $block20
                                                      (i32.ne
                                                        (array.len
                                                          (local.tee $1
                                                            (struct.get $values 0
                                                              (ref.cast (ref $values) (local.get $13))
                                                            )
                                                          )
                                                        )
                                                        (i32.const 1)
                                                      )
                                                    )
                                                    (br $block23
                                                      (array.get $vector (local.get $1) (i32.const 0))
                                                    )
                                                  )
                                                )
                                                (local.get $13)
                                              )
                                            )
                                            (return_call_ref $call
                                              (struct.get $closure 1
                                                (local.tee $20
                                                  (ref.cast
                                                    (ref $closure)
                                                    (block $block24
                                                      (result eqref)
                                                      (br_if $block15
                                                        (i32.or
                                                          (ref.is_null (local.get $15))
                                                          (ref.eq (local.get $15) (global.get $uninitialized))
                                                        )
                                                      )
                                                      (if
                                                        (ref.test (ref $values) (local.get $15))
                                                        (then
                                                          (br_if $block20
                                                            (i32.ne
                                                              (array.len
                                                                (local.tee $1
                                                                  (struct.get $values 0
                                                                    (ref.cast (ref $values) (local.get $15))
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
                                                      (local.get $15)
                                                    )
                                                  )
                                                )
                                              )
                                              (array.new_fixed $vector 1 (local.get $0))
                                              (local.get $2)
                                              (struct.get $closure 0 (local.get $20))
                                            )
                                          )
                                        )
                                        (unreachable)
                                      )
                                      (br $block16)
                                    )
                                  )
                                )
                                (else
                                  (br_if $block15
                                    (i32.or
                                      (ref.is_null (local.get $9))
                                      (ref.eq (local.get $9) (global.get $uninitialized))
                                    )
                                  )
                                  (local.set $0
                                    (block $block26
                                      (result eqref)
                                      (br_if $block15
                                        (i32.or
                                          (ref.is_null (local.get $8))
                                          (ref.eq (local.get $8) (global.get $uninitialized))
                                        )
                                      )
                                      (if
                                        (ref.test (ref $values) (local.get $8))
                                        (then
                                          (br_if $block18
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
                                          (br $block26 (array.get $vector (local.get $1) (i32.const 0)))
                                        )
                                      )
                                      (local.get $8)
                                    )
                                  )
                                  (local.set $10
                                    (block $block27
                                      (result eqref)
                                      (br_if $block15
                                        (i32.or
                                          (ref.is_null (local.get $10))
                                          (ref.eq (local.get $10) (global.get $uninitialized))
                                        )
                                      )
                                      (if
                                        (ref.test (ref $values) (local.get $10))
                                        (then
                                          (br_if $block18
                                            (i32.ne
                                              (array.len
                                                (local.tee $1
                                                  (struct.get $values 0
                                                    (ref.cast (ref $values) (local.get $10))
                                                  )
                                                )
                                              )
                                              (i32.const 1)
                                            )
                                          )
                                          (br $block27 (array.get $vector (local.get $1) (i32.const 0)))
                                        )
                                      )
                                      (local.get $10)
                                    )
                                  )
                                  (array.set $vector
                                    (ref.cast (ref $vector) (local.get $9))
                                    (block
                                      (result i32)
                                      (br_if $block9
                                        (i64.gt_u
                                          (local.tee $7
                                            (if
                                              (result i64)
                                              (ref.test (ref i31) (local.get $0))
                                              (then
                                                (i64.extend_i32_s
                                                  (i31.get_s (ref.cast (ref i31) (local.get $0)))
                                                )
                                              )
                                              (else
                                                (if
                                                  (result i64)
                                                  (ref.test (ref $integer) (local.get $0))
                                                  (then
                                                    (struct.get $integer 0
                                                      (ref.cast (ref $integer) (local.get $0))
                                                    )
                                                  )
                                                  (else (br $block8))
                                                )
                                              )
                                            )
                                          )
                                          (i64.const 2147483647)
                                        )
                                      )
                                      (i32.wrap_i64 (local.get $7))
                                    )
                                    (local.get $10)
                                  )
                                  (local.set $23 (ref.i31 (i32.const 1)))
                                  (local.set $0
                                    (if
                                      (result eqref)
                                      (ref.test
                                        (ref i31)
                                        (local.tee $0
                                          (block $block28
                                            (result eqref)
                                            (br_if $block15
                                              (i32.or
                                                (ref.is_null (local.get $8))
                                                (ref.eq (local.get $8) (global.get $uninitialized))
                                              )
                                            )
                                            (if
                                              (ref.test (ref $values) (local.get $8))
                                              (then
                                                (br_if $block18
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
                                                (br $block28 (array.get $vector (local.get $1) (i32.const 0)))
                                              )
                                            )
                                            (local.get $8)
                                          )
                                        )
                                      )
                                      (then
                                        (if
                                          (result eqref)
                                          (i32.le_u
                                            (i32.add
                                              (local.tee $3
                                                (i32.add
                                                  (i31.get_s (ref.cast (ref i31) (local.get $0)))
                                                  (i32.const 1)
                                                )
                                              )
                                              (i32.const 1073741824)
                                            )
                                            (i32.const 2147483647)
                                          )
                                          (then (ref.i31 (local.get $3)))
                                          (else (call $cold.checked_add (local.get $0) (local.get $23)))
                                        )
                                      )
                                      (else (call $cold.checked_add (local.get $0) (local.get $23)))
                                    )
                                  )
                                  (local.set $8
                                    (block $block29
                                      (result eqref)
                                      (br_if $block15
                                        (i32.or
                                          (ref.is_null (local.get $13))
                                          (ref.eq (local.get $13) (global.get $uninitialized))
                                        )
                                      )
                                      (if
                                        (ref.test (ref $values) (local.get $13))
                                        (then
                                          (br_if $block18
                                            (i32.ne
                                              (array.len
                                                (local.tee $1
                                                  (struct.get $values 0
                                                    (ref.cast (ref $values) (local.get $13))
                                                  )
                                                )
                                              )
                                              (i32.const 1)
                                            )
                                          )
                                          (br $block29 (array.get $vector (local.get $1) (i32.const 0)))
                                        )
                                      )
                                      (local.get $13)
                                    )
                                  )
                                  (return_call_ref $call
                                    (struct.get $closure 1
                                      (local.tee $20
                                        (ref.cast
                                          (ref $closure)
                                          (block $block30
                                            (result eqref)
                                            (br_if $block15
                                              (i32.or
                                                (ref.is_null (local.get $14))
                                                (ref.eq (local.get $14) (global.get $uninitialized))
                                              )
                                            )
                                            (if
                                              (ref.test (ref $values) (local.get $14))
                                              (then
                                                (br_if $block18
                                                  (i32.ne
                                                    (array.len
                                                      (local.tee $1
                                                        (struct.get $values 0
                                                          (ref.cast (ref $values) (local.get $14))
                                                        )
                                                      )
                                                    )
                                                    (i32.const 1)
                                                  )
                                                )
                                                (br $block30 (array.get $vector (local.get $1) (i32.const 0)))
                                              )
                                            )
                                            (local.get $14)
                                          )
                                        )
                                      )
                                    )
                                    (array.new_fixed $vector 2 (local.get $0) (local.get $8))
                                    (local.get $2)
                                    (struct.get $closure 0 (local.get $20))
                                  )
                                )
                              )
                              (unreachable)
                            )
                            (br $block16)
                          )
                          (else (global.get $false))
                        )
                      )
                    )
                    (br $block2)
                  )
                  (br $block1)
                )
              )
            )
            (global.set $error_code (i32.const 1))
            (local.set $3 (i32.load (i32.const 1062292)))
            (br $block (i32.load (i32.const 1062332)))
          )
          (global.set $error_code (i32.const 3))
          (local.set $3 (i32.load (i32.const 1062300)))
          (br $block (i32.load (i32.const 1062340)))
        )
        (global.set $error_code (i32.const 5))
        (local.set $3 (i32.load (i32.const 1062308)))
        (br $block (i32.load (i32.const 1062348)))
      )
      (global.set $error_code (i32.const 6))
      (local.set $3 (i32.load (i32.const 1062312)))
      (i32.load (i32.const 1062352))
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
