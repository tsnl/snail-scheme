(func $function184
  (type $result_guard_fn_0_0)
  (param $0 eqref)
  (result eqref)
  (local $1 (ref $vector))
  (local $2 eqref)
  (local $3 eqref)
  (local $4 eqref)
  (local $5 eqref)
  (local $6 eqref)
  (local $7 (ref null $closure))
  (local $8 (ref null $closure))
  (local $9 (ref $pair))
  (local $10 i32)
  (local $11 i32)
  (local $12 i32)
  (local $13 i32)
  (local $scratch eqref)
  (local.set $12
    (block $block41
      (result i32)
      (block $block1
        (block $block
          (return
            (if
              (result (ref eq))
              (ref.eq
                (select
                  (result (ref $atom))
                  (global.get $true)
                  (global.get $false)
                  (ref.test
                    (ref $pair)
                    (block $block2
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
                                (local.tee $1 (struct.get $values 0 (ref.cast (ref $values) (local.get $0))))
                              )
                              (i32.const 1)
                            )
                          )
                          (br $block2 (array.get $vector (local.get $1) (i32.const 0)))
                        )
                      )
                      (local.get $0)
                    )
                  )
                )
                (block
                  (result (ref $atom))
                  (br_if $block (ref.is_null (local.tee $7 (global.get $g207))))
                  (drop (ref.as_non_null (local.get $7)))
                  (global.get $false)
                )
              )
              (then
                (ref.i31
                  (i32.ne
                    (block $block4
                      (result i32)
                      (drop
                        (br_if $block4
                          (i32.const 1)
                          (ref.eq
                            (local.tee $0
                              (block $block3
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
                                          (local.tee $1
                                            (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                          )
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
                            (global.get $literal14)
                          )
                        )
                      )
                      (if
                        (i32.and
                          (if
                            (result i32)
                            (ref.test (ref $atom) (local.get $0))
                            (then
                              (i32.lt_s
                                (struct.get $atom 0 (ref.cast (ref $atom) (local.get $0)))
                                (i32.const 0)
                              )
                            )
                            (else (i32.const 0))
                          )
                          (i32.const 1)
                        )
                        (then
                          (br $block4
                            (i32.eq
                              (struct.get $atom 0 (ref.cast (ref $atom) (local.get $0)))
                              (i32.const -2147483645)
                            )
                          )
                        )
                      )
                      (i32.const 0)
                    )
                    (i32.const 0)
                  )
                )
              )
              (else
                (if
                  (result (ref $pair))
                  (block $block7
                    (result i32)
                    (drop
                      (br_if $block7
                        (i32.const 1)
                        (ref.eq
                          (local.tee $2
                            (block $block6
                              (result eqref)
                              (if
                                (ref.test
                                  (ref $values)
                                  (local.tee $2
                                    (struct.get $pair 0
                                      (ref.cast
                                        (ref $pair)
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
                                                    (local.tee $1
                                                      (struct.get $values 0
                                                        (ref.cast (ref $values) (local.get $0))
                                                      )
                                                    )
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
                                    )
                                  )
                                )
                                (then
                                  (br_if $block1
                                    (i32.ne
                                      (array.len
                                        (local.tee $1
                                          (struct.get $values 0 (ref.cast (ref $values) (local.get $2)))
                                        )
                                      )
                                      (i32.const 1)
                                    )
                                  )
                                  (br $block6 (array.get $vector (local.get $1) (i32.const 0)))
                                )
                              )
                              (local.get $2)
                            )
                          )
                          (global.get $literal15)
                        )
                      )
                    )
                    (if
                      (i32.and
                        (if
                          (result i32)
                          (ref.test (ref $atom) (local.get $2))
                          (then
                            (i32.lt_s
                              (struct.get $atom 0 (ref.cast (ref $atom) (local.get $2)))
                              (i32.const 0)
                            )
                          )
                          (else (i32.const 0))
                        )
                        (i32.const 1)
                      )
                      (then
                        (br $block7
                          (i32.eq
                            (struct.get $atom 0 (ref.cast (ref $atom) (local.get $2)))
                            (i32.const -2147483644)
                          )
                        )
                      )
                    )
                    (i32.const 0)
                  )
                  (then
                    (br_if $block (ref.is_null (local.tee $7 (global.get $g306))))
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
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block8 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $0)
                                  )
                                )
                              )
                            )
                          )
                          (then
                            (br_if $block1
                              (i32.ne
                                (array.len
                                  (local.tee $1
                                    (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                  )
                                )
                                (i32.const 1)
                              )
                            )
                            (br $block9 (array.get $vector (local.get $1) (i32.const 0)))
                          )
                        )
                        (local.get $0)
                      )
                    )
                    (br_if $block (ref.is_null (local.tee $8 (global.get $g231))))
                    (drop (ref.as_non_null (local.get $8)))
                    (struct.new $pair
                      (global.get $literal15)
                      (block $block10
                        (result eqref)
                        (if
                          (ref.test
                            (ref $values)
                            (local.tee $0
                              (call $function39
                                (local.get $7)
                                (local.get $0)
                                (global.get $nil)
                                (ref.null none)
                              )
                            )
                          )
                          (then
                            (br_if $block1
                              (i32.ne
                                (array.len
                                  (local.tee $1
                                    (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                  )
                                )
                                (i32.const 1)
                              )
                            )
                            (br $block10 (array.get $vector (local.get $1) (i32.const 0)))
                          )
                        )
                        (local.get $0)
                      )
                    )
                  )
                  (else
                    (if
                      (result (ref $pair))
                      (block $block13
                        (result i32)
                        (drop
                          (br_if $block13
                            (i32.const 1)
                            (ref.eq
                              (local.tee $2
                                (block $block12
                                  (result eqref)
                                  (if
                                    (ref.test
                                      (ref $values)
                                      (local.tee $2
                                        (struct.get $pair 0
                                          (ref.cast
                                            (ref $pair)
                                            (block $block11
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
                                      )
                                    )
                                    (then
                                      (br_if $block1
                                        (i32.ne
                                          (array.len
                                            (local.tee $1
                                              (struct.get $values 0 (ref.cast (ref $values) (local.get $2)))
                                            )
                                          )
                                          (i32.const 1)
                                        )
                                      )
                                      (br $block12 (array.get $vector (local.get $1) (i32.const 0)))
                                    )
                                  )
                                  (local.get $2)
                                )
                              )
                              (global.get $literal16)
                            )
                          )
                        )
                        (if
                          (i32.and
                            (if
                              (result i32)
                              (ref.test (ref $atom) (local.get $2))
                              (then
                                (i32.lt_s
                                  (struct.get $atom 0 (ref.cast (ref $atom) (local.get $2)))
                                  (i32.const 0)
                                )
                              )
                              (else (i32.const 0))
                            )
                            (i32.const 1)
                          )
                          (then
                            (br $block13
                              (i32.eq
                                (struct.get $atom 0 (ref.cast (ref $atom) (local.get $2)))
                                (i32.const -2147483643)
                              )
                            )
                          )
                        )
                        (i32.const 0)
                      )
                      (then
                        (br_if $block (ref.is_null (local.tee $7 (global.get $g306))))
                        (local.set $0
                          (block $block15
                            (result eqref)
                            (if
                              (ref.test
                                (ref $values)
                                (local.tee $0
                                  (struct.get $pair 1
                                    (ref.cast
                                      (ref $pair)
                                      (block $block14
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
                                                  (local.tee $1
                                                    (struct.get $values 0
                                                      (ref.cast (ref $values) (local.get $0))
                                                    )
                                                  )
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
                                  )
                                )
                              )
                              (then
                                (br_if $block1
                                  (i32.ne
                                    (array.len
                                      (local.tee $1
                                        (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                      )
                                    )
                                    (i32.const 1)
                                  )
                                )
                                (br $block15 (array.get $vector (local.get $1) (i32.const 0)))
                              )
                            )
                            (local.get $0)
                          )
                        )
                        (br_if $block (ref.is_null (local.tee $8 (global.get $g231))))
                        (drop (ref.as_non_null (local.get $8)))
                        (struct.new $pair
                          (global.get $literal16)
                          (block $block16
                            (result eqref)
                            (if
                              (ref.test
                                (ref $values)
                                (local.tee $0
                                  (call $function39
                                    (local.get $7)
                                    (local.get $0)
                                    (global.get $nil)
                                    (ref.null none)
                                  )
                                )
                              )
                              (then
                                (br_if $block1
                                  (i32.ne
                                    (array.len
                                      (local.tee $1
                                        (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                      )
                                    )
                                    (i32.const 1)
                                  )
                                )
                                (br $block16 (array.get $vector (local.get $1) (i32.const 0)))
                              )
                            )
                            (local.get $0)
                          )
                        )
                      )
                      (else
                        (if
                          (result (ref $pair))
                          (block $block19
                            (result i32)
                            (drop
                              (br_if $block19
                                (i32.const 1)
                                (ref.eq
                                  (local.tee $2
                                    (block $block18
                                      (result eqref)
                                      (if
                                        (ref.test
                                          (ref $values)
                                          (local.tee $2
                                            (struct.get $pair 0
                                              (ref.cast
                                                (ref $pair)
                                                (block $block17
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
                                                            (local.tee $1
                                                              (struct.get $values 0
                                                                (ref.cast (ref $values) (local.get $0))
                                                              )
                                                            )
                                                          )
                                                          (i32.const 1)
                                                        )
                                                      )
                                                      (br $block17
                                                        (array.get $vector (local.get $1) (i32.const 0))
                                                      )
                                                    )
                                                  )
                                                  (local.get $0)
                                                )
                                              )
                                            )
                                          )
                                        )
                                        (then
                                          (br_if $block1
                                            (i32.ne
                                              (array.len
                                                (local.tee $1
                                                  (struct.get $values 0
                                                    (ref.cast (ref $values) (local.get $2))
                                                  )
                                                )
                                              )
                                              (i32.const 1)
                                            )
                                          )
                                          (br $block18 (array.get $vector (local.get $1) (i32.const 0)))
                                        )
                                      )
                                      (local.get $2)
                                    )
                                  )
                                  (global.get $literal17)
                                )
                              )
                            )
                            (if
                              (i32.and
                                (if
                                  (result i32)
                                  (ref.test (ref $atom) (local.get $2))
                                  (then
                                    (i32.lt_s
                                      (struct.get $atom 0 (ref.cast (ref $atom) (local.get $2)))
                                      (i32.const 0)
                                    )
                                  )
                                  (else (i32.const 0))
                                )
                                (i32.const 1)
                              )
                              (then
                                (br $block19
                                  (i32.eq
                                    (struct.get $atom 0 (ref.cast (ref $atom) (local.get $2)))
                                    (i32.const -2147483642)
                                  )
                                )
                              )
                            )
                            (i32.const 0)
                          )
                          (then
                            (local.set $2
                              (block $block20
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
                            (local.set $0
                              (block $block22
                                (result eqref)
                                (if
                                  (ref.test
                                    (ref $values)
                                    (local.tee $0
                                      (struct.get $pair 1
                                        (ref.cast
                                          (ref $pair)
                                          (block $block21
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
                                                      (local.tee $1
                                                        (struct.get $values 0
                                                          (ref.cast (ref $values) (local.get $0))
                                                        )
                                                      )
                                                    )
                                                    (i32.const 1)
                                                  )
                                                )
                                                (br $block21 (array.get $vector (local.get $1) (i32.const 0)))
                                              )
                                            )
                                            (local.get $0)
                                          )
                                        )
                                      )
                                    )
                                  )
                                  (then
                                    (br_if $block1
                                      (i32.ne
                                        (array.len
                                          (local.tee $1
                                            (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                          )
                                        )
                                        (i32.const 1)
                                      )
                                    )
                                    (br $block22 (array.get $vector (local.get $1) (i32.const 0)))
                                  )
                                )
                                (local.get $0)
                              )
                            )
                            (br_if $block (ref.is_null (local.tee $7 (global.get $g231))))
                            (drop (ref.as_non_null (local.get $7)))
                            (local.set $9
                              (struct.new $pair
                                (global.get $literal15)
                                (block $block23
                                  (result eqref)
                                  (if
                                    (ref.test
                                      (ref $values)
                                      (local.tee $0
                                        (call $function39
                                          (struct.new $closure
                                            (ref.func $adapter185)
                                            (array.new_fixed $vector 0)
                                          )
                                          (local.get $0)
                                          (global.get $nil)
                                          (ref.null none)
                                        )
                                      )
                                    )
                                    (then
                                      (br_if $block1
                                        (i32.ne
                                          (array.len
                                            (local.tee $1
                                              (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                            )
                                          )
                                          (i32.const 1)
                                        )
                                      )
                                      (br $block23 (array.get $vector (local.get $1) (i32.const 0)))
                                    )
                                  )
                                  (local.get $0)
                                )
                              )
                            )
                            (br_if $block (ref.is_null (local.tee $7 (global.get $g208))))
                            (drop (ref.as_non_null (local.get $7)))
                            (struct.new $pair
                              (global.get $literal17)
                              (struct.new $pair
                                (local.get $2)
                                (struct.new $pair (local.get $9) (global.get $nil))
                              )
                            )
                          )
                          (else
                            (if
                              (result (ref $pair))
                              (block $block26
                                (result i32)
                                (drop
                                  (br_if $block26
                                    (i32.const 1)
                                    (ref.eq
                                      (local.tee $2
                                        (block $block25
                                          (result eqref)
                                          (if
                                            (ref.test
                                              (ref $values)
                                              (local.tee $2
                                                (struct.get $pair 0
                                                  (ref.cast
                                                    (ref $pair)
                                                    (block $block24
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
                                                                (local.tee $1
                                                                  (struct.get $values 0
                                                                    (ref.cast (ref $values) (local.get $0))
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
                                                      (local.get $0)
                                                    )
                                                  )
                                                )
                                              )
                                            )
                                            (then
                                              (br_if $block1
                                                (i32.ne
                                                  (array.len
                                                    (local.tee $1
                                                      (struct.get $values 0
                                                        (ref.cast (ref $values) (local.get $2))
                                                      )
                                                    )
                                                  )
                                                  (i32.const 1)
                                                )
                                              )
                                              (br $block25 (array.get $vector (local.get $1) (i32.const 0)))
                                            )
                                          )
                                          (local.get $2)
                                        )
                                      )
                                      (global.get $literal18)
                                    )
                                  )
                                )
                                (if
                                  (i32.and
                                    (if
                                      (result i32)
                                      (ref.test (ref $atom) (local.get $2))
                                      (then
                                        (i32.lt_s
                                          (struct.get $atom 0 (ref.cast (ref $atom) (local.get $2)))
                                          (i32.const 0)
                                        )
                                      )
                                      (else (i32.const 0))
                                    )
                                    (i32.const 1)
                                  )
                                  (then
                                    (br $block26
                                      (i32.eq
                                        (struct.get $atom 0 (ref.cast (ref $atom) (local.get $2)))
                                        (i32.const -2147483641)
                                      )
                                    )
                                  )
                                )
                                (i32.const 0)
                              )
                              (then
                                (local.set $2
                                  (block $block27
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
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block27 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $0)
                                  )
                                )
                                (br_if $block (ref.is_null (local.tee $7 (global.get $g210))))
                                (drop (ref.as_non_null (local.get $7)))
                                (local.set $2
                                  (block $block28
                                    (result eqref)
                                    (if
                                      (ref.test (ref $values) (local.tee $2 (call $function3 (local.get $2))))
                                      (then
                                        (br_if $block1
                                          (i32.ne
                                            (array.len
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $2)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block28 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $2)
                                  )
                                )
                                (br_if $block (ref.is_null (local.tee $7 (global.get $g306))))
                                (drop (ref.as_non_null (local.get $7)))
                                (local.set $3
                                  (block $block29
                                    (result eqref)
                                    (if
                                      (ref.test
                                        (ref $values)
                                        (local.tee $2 (call $function184 (local.get $2)))
                                      )
                                      (then
                                        (br_if $block1
                                          (i32.ne
                                            (array.len
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $2)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block29 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $2)
                                  )
                                )
                                (local.set $2
                                  (block $block30
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
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block30 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $0)
                                  )
                                )
                                (br_if $block (ref.is_null (local.tee $7 (global.get $g285))))
                                (drop (ref.as_non_null (local.get $7)))
                                (local.set $4
                                  (block $block31
                                    (result eqref)
                                    (if
                                      (ref.test
                                        (ref $values)
                                        (local.tee $2 (call $function163 (local.get $2)))
                                      )
                                      (then
                                        (br_if $block1
                                          (i32.ne
                                            (array.len
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $2)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block31 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $2)
                                  )
                                )
                                (br_if $block (ref.is_null (local.tee $7 (global.get $g208))))
                                (drop (ref.as_non_null (local.get $7)))
                                (local.set $2
                                  (block $block32
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
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block32 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $0)
                                  )
                                )
                                (br_if $block (ref.is_null (local.tee $7 (global.get $g210))))
                                (drop (ref.as_non_null (local.get $7)))
                                (local.set $5
                                  (block $block33
                                    (result eqref)
                                    (if
                                      (ref.test (ref $values) (local.tee $2 (call $function3 (local.get $2))))
                                      (then
                                        (br_if $block1
                                          (i32.ne
                                            (array.len
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $2)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block33 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $2)
                                  )
                                )
                                (local.set $2
                                  (block $block34
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
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block34 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $0)
                                  )
                                )
                                (br_if $block (ref.is_null (local.tee $7 (global.get $g285))))
                                (drop (ref.as_non_null (local.get $7)))
                                (local.set $6
                                  (block $block35
                                    (result eqref)
                                    (if
                                      (ref.test
                                        (ref $values)
                                        (local.tee $2 (call $function163 (local.get $2)))
                                      )
                                      (then
                                        (br_if $block1
                                          (i32.ne
                                            (array.len
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $2)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block35 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $2)
                                  )
                                )
                                (local.set $2
                                  (block $block36
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
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block36 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $0)
                                  )
                                )
                                (br_if $block (ref.is_null (local.tee $7 (global.get $g285))))
                                (drop (ref.as_non_null (local.get $7)))
                                (local.set $2
                                  (block $block37
                                    (result eqref)
                                    (if
                                      (ref.test
                                        (ref $values)
                                        (local.tee $2 (call $function163 (local.get $2)))
                                      )
                                      (then
                                        (br_if $block1
                                          (i32.ne
                                            (array.len
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $2)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block37 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $2)
                                  )
                                )
                                (local.set $0
                                  (block $block38
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
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block38 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $0)
                                  )
                                )
                                (br_if $block (ref.is_null (local.tee $7 (global.get $g285))))
                                (drop (ref.as_non_null (local.get $7)))
                                (local.set $0
                                  (block $block39
                                    (result eqref)
                                    (if
                                      (ref.test
                                        (ref $values)
                                        (local.tee $0 (call $function163 (local.get $0)))
                                      )
                                      (then
                                        (br_if $block1
                                          (i32.ne
                                            (array.len
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block39 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $0)
                                  )
                                )
                                (br_if $block (ref.is_null (local.tee $7 (global.get $g306))))
                                (drop (ref.as_non_null (local.get $7)))
                                (local.set $0
                                  (block $block40
                                    (result eqref)
                                    (if
                                      (ref.test
                                        (ref $values)
                                        (local.tee $0 (call $function184 (local.get $0)))
                                      )
                                      (then
                                        (br_if $block1
                                          (i32.ne
                                            (array.len
                                              (local.tee $1
                                                (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                        (br $block40 (array.get $vector (local.get $1) (i32.const 0)))
                                      )
                                    )
                                    (local.get $0)
                                  )
                                )
                                (br_if $block (ref.is_null (local.tee $7 (global.get $g208))))
                                (drop (ref.as_non_null (local.get $7)))
                                (br_if $block (ref.is_null (local.tee $7 (global.get $g208))))
                                (drop (ref.as_non_null (local.get $7)))
                                (br_if $block (ref.is_null (local.tee $7 (global.get $g208))))
                                (drop (ref.as_non_null (local.get $7)))
                                (struct.new $pair
                                  (global.get $literal16)
                                  (struct.new $pair
                                    (struct.new $pair
                                      (global.get $literal18)
                                      (struct.new $pair
                                        (local.get $3)
                                        (struct.new $pair (local.get $4) (global.get $nil))
                                      )
                                    )
                                    (struct.new $pair
                                      (struct.new $pair
                                        (global.get $literal18)
                                        (struct.new $pair
                                          (local.get $5)
                                          (struct.new $pair
                                            (struct.new $pair
                                              (global.get $literal17)
                                              (struct.new $pair
                                                (local.get $6)
                                                (struct.new $pair
                                                  (local.get $2)
                                                  (struct.new $pair (local.get $0) (global.get $nil))
                                                )
                                              )
                                            )
                                            (global.get $nil)
                                          )
                                        )
                                      )
                                      (global.get $nil)
                                    )
                                  )
                                )
                              )
                              (else
                                (br_if $block (ref.is_null (local.tee $7 (global.get $g122))))
                                (drop (struct.get $closure 1 (local.get $7)))
                                (return
                                  (block
                                    (result eqref)
                                    (local.set $scratch
                                      (call $abi_take
                                        (call $snail:error
                                          (local.tee $10
                                            (call $abi_root
                                              (array.new_fixed $vector 2
                                                (global.get $false)
                                                (global.get $literal19)
                                              )
                                            )
                                          )
                                        )
                                      )
                                    )
                                    (if
                                      (i32.ge_u (local.get $10) (global.get $abi_used))
                                      (then (unreachable))
                                    )
                                    (if
                                      (i32.ne
                                        (array.get $text (global.get $abi_links) (local.get $10))
                                        (i32.const -1)
                                      )
                                      (then (unreachable))
                                    )
                                    (drop (table.get $abi_roots (local.get $10)))
                                    (table.set $abi_roots (local.get $10) (ref.null none))
                                    (array.set $text
                                      (global.get $abi_links)
                                      (local.get $10)
                                      (global.get $abi_free)
                                    )
                                    (global.set $abi_free (local.get $10))
                                    (global.set $abi_live (i32.sub (global.get $abi_live) (i32.const 1)))
                                    (local.get $scratch)
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
        (global.set $error_code (i32.const 6))
        (local.set $11 (i32.load (i32.const 1062312)))
        (br $block41 (i32.load (i32.const 1062352)))
      )
      (global.set $error_code (i32.const 5))
      (local.set $11 (i32.load (i32.const 1062308)))
      (i32.load (i32.const 1062348))
    )
  )
  (global.set $__stack_pointer (local.tee $10 (i32.sub (global.get $__stack_pointer) (i32.const 32))))
  (call $_RNvMNtCsi9YzqDQQz2q_5alloc6stringNtB2_6String15from_utf8_lossy
    (local.tee $13 (i32.add (local.get $10) (i32.const 12)))
    (local.get $12)
    (local.get $11)
  )
  (i64.store offset=24 (local.get $10) (i64.or (i64.extend_i32_u (local.get $13)) (i64.const 103079215104)))
  (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio7__eprint (i32.add (local.get $10) (i32.const 24)))
  (local.set $11 (i32.load offset=16 (local.get $10)))
  (if (i32.gt_s (i32.load offset=12 (local.get $10)) (i32.const 0)) (then (call $dlfree (local.get $11))))
  (call $_RNvNtCset5xJoy1xWQ_3std2rt7cleanup)
  (call $__imported_wasi_snapshot_preview1_proc_exit (i32.const 1))
  (unreachable)
)
