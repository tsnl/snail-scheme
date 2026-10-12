;; Exact original optimized function $function178, import-inclusive index 179.
;; Full module and referenced definitions are retained in raw-artifacts.tar.xz.
(func $function178
  (type $32)
  (param $0 eqref)
  (param $1 eqref)
  (param $2 nullref)
  (result eqref)
  (local $3 eqref)
  (local $4 eqref)
  (local $5 eqref)
  (local $6 eqref)
  (local $7 eqref)
  (local $8 eqref)
  (local $9 (ref $vector))
  (local $10 (ref $vector))
  (local $11 (ref null $closure))
  (local $12 (ref i31))
  (local $13 (ref struct))
  (local $14 i32)
  (local $15 i32)
  (local $16 i32)
  (local $17 i32)
  (local.set $16
    (block $block26
      (result i32)
      (block $block1
        (block $block
          (return
            (if
              (result (ref $atom))
              (ref.eq
                (call $numeric_equal
                  (block $block2
                    (result eqref)
                    (br_if $block
                      (i32.or
                        (ref.is_null
                          (local.tee $3
                            (array.get $vector (ref.cast (ref $vector) (local.get $0)) (i32.const 0))
                          )
                        )
                        (ref.eq (local.get $3) (global.get $uninitialized))
                      )
                    )
                    (if
                      (ref.test (ref $values) (local.get $3))
                      (then
                        (br_if $block1
                          (i32.ne
                            (array.len
                              (local.tee $9 (struct.get $values 0 (ref.cast (ref $values) (local.get $3))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block2 (array.get $vector (local.get $9) (i32.const 0)))
                      )
                    )
                    (local.get $3)
                  )
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
                              (local.tee $9 (struct.get $values 0 (ref.cast (ref $values) (local.get $1))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block3 (array.get $vector (local.get $9) (i32.const 0)))
                      )
                    )
                    (local.get $1)
                  )
                )
                (global.get $false)
              )
              (then
                (br_if $block
                  (i32.or
                    (ref.is_null
                      (local.tee $0
                        (array.get $vector
                          (local.tee $9 (ref.cast (ref $vector) (local.get $0)))
                          (i32.const 5)
                        )
                      )
                    )
                    (ref.eq (local.get $0) (global.get $uninitialized))
                  )
                )
                (local.set $3
                  (block $block4
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
                              (local.tee $10 (struct.get $values 0 (ref.cast (ref $values) (local.get $1))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block4 (array.get $vector (local.get $10) (i32.const 0)))
                      )
                    )
                    (local.get $1)
                  )
                )
                (local.set $3
                  (block $block5
                    (result eqref)
                    (br_if $block (ref.is_null (local.tee $11 (global.get $g63))))
                    (if
                      (ref.test
                        (ref $values)
                        (local.tee $0
                          (call $primitive63
                            (struct.get $closure 1 (local.get $11))
                            (array.new_fixed $vector 2 (local.get $0) (local.get $3))
                            (ref.null none)
                          )
                        )
                      )
                      (then
                        (br_if $block1
                          (i32.ne
                            (array.len
                              (local.tee $10 (struct.get $values 0 (ref.cast (ref $values) (local.get $0))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block5 (array.get $vector (local.get $10) (i32.const 0)))
                      )
                    )
                    (local.get $0)
                  )
                )
                (local.set $0
                  (block $block6
                    (result eqref)
                    (br_if $block
                      (i32.or
                        (ref.is_null (local.tee $0 (array.get $vector (local.get $9) (i32.const 6))))
                        (ref.eq (local.get $0) (global.get $uninitialized))
                      )
                    )
                    (if
                      (ref.test (ref $values) (local.get $0))
                      (then
                        (br_if $block1
                          (i32.ne
                            (array.len
                              (local.tee $10 (struct.get $values 0 (ref.cast (ref $values) (local.get $0))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block6 (array.get $vector (local.get $10) (i32.const 0)))
                      )
                    )
                    (local.get $0)
                  )
                )
                (local.set $5
                  (block $block7
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
                              (local.tee $10 (struct.get $values 0 (ref.cast (ref $values) (local.get $1))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block7 (array.get $vector (local.get $10) (i32.const 0)))
                      )
                    )
                    (local.get $1)
                  )
                )
                (local.set $5
                  (block $block8
                    (result eqref)
                    (br_if $block (ref.is_null (local.tee $11 (global.get $g63))))
                    (if
                      (ref.test
                        (ref $values)
                        (local.tee $0
                          (call $primitive63
                            (struct.get $closure 1 (local.get $11))
                            (array.new_fixed $vector 2 (local.get $0) (local.get $5))
                            (ref.null none)
                          )
                        )
                      )
                      (then
                        (br_if $block1
                          (i32.ne
                            (array.len
                              (local.tee $10 (struct.get $values 0 (ref.cast (ref $values) (local.get $0))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block8 (array.get $vector (local.get $10) (i32.const 0)))
                      )
                    )
                    (local.get $0)
                  )
                )
                (return
                  (block $block25
                    (result (ref $atom))
                    (local.set $4 (array.get $vector (local.get $9) (i32.const 1)))
                    (local.set $0 (array.get $vector (local.get $9) (i32.const 2)))
                    (local.set $7 (array.get $vector (local.get $9) (i32.const 3)))
                    (local.set $8 (array.get $vector (local.get $9) (i32.const 4)))
                    (local.set $6 (array.get $vector (local.get $9) (i32.const 0)))
                    (br_if $block
                      (i32.or
                        (ref.is_null (local.get $3))
                        (ref.eq (local.get $3) (global.get $uninitialized))
                      )
                    )
                    (br_if $block
                      (i32.or
                        (ref.is_null (local.get $4))
                        (ref.eq (local.get $4) (global.get $uninitialized))
                      )
                    )
                    (br_if $block
                      (i32.or
                        (ref.is_null (local.get $5))
                        (ref.eq (local.get $5) (global.get $uninitialized))
                      )
                    )
                    (block $block9
                      (br $block25
                        (if
                          (result (ref $atom))
                          (block $block11
                            (result i32)
                            (drop
                              (br_if $block11
                                (i32.const 1)
                                (ref.eq
                                  (local.get $3)
                                  (local.tee $4
                                    (block $block10
                                      (result eqref)
                                      (br_if $block (ref.is_null (local.tee $11 (global.get $g63))))
                                      (if
                                        (ref.test
                                          (ref $values)
                                          (local.tee $4
                                            (call $primitive63
                                              (struct.get $closure 1 (local.get $11))
                                              (array.new_fixed $vector 2 (local.get $4) (local.get $5))
                                              (ref.null none)
                                            )
                                          )
                                        )
                                        (then
                                          (br_if $block9
                                            (i32.ne
                                              (array.len
                                                (local.tee $9
                                                  (struct.get $values 0
                                                    (ref.cast (ref $values) (local.get $4))
                                                  )
                                                )
                                              )
                                              (i32.const 1)
                                            )
                                          )
                                          (br $block10 (array.get $vector (local.get $9) (i32.const 0)))
                                        )
                                      )
                                      (local.get $4)
                                    )
                                  )
                                )
                              )
                            )
                            (if
                              (i32.and
                                (if
                                  (result i32)
                                  (ref.test (ref $atom) (local.get $3))
                                  (then
                                    (i32.lt_s
                                      (struct.get $atom 0 (ref.cast (ref $atom) (local.get $3)))
                                      (i32.const 0)
                                    )
                                  )
                                  (else (i32.const 0))
                                )
                                (if
                                  (result i32)
                                  (ref.test (ref $atom) (local.get $4))
                                  (then
                                    (i32.lt_s
                                      (struct.get $atom 0 (ref.cast (ref $atom) (local.get $4)))
                                      (i32.const 0)
                                    )
                                  )
                                  (else (i32.const 0))
                                )
                              )
                              (then
                                (br $block11
                                  (i32.eq
                                    (struct.get $atom 0 (ref.cast (ref $atom) (local.get $3)))
                                    (struct.get $atom 0 (ref.cast (ref $atom) (local.get $4)))
                                  )
                                )
                              )
                            )
                            (i32.const 0)
                          )
                          (then
                            (local.set $3
                              (block $block12
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
                                    (br_if $block9
                                      (i32.ne
                                        (array.len
                                          (local.tee $9
                                            (struct.get $values 0 (ref.cast (ref $values) (local.get $0)))
                                          )
                                        )
                                        (i32.const 1)
                                      )
                                    )
                                    (br $block12 (array.get $vector (local.get $9) (i32.const 0)))
                                  )
                                )
                                (local.get $0)
                              )
                            )
                            (local.set $4
                              (block $block13
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
                                    (br_if $block9
                                      (i32.ne
                                        (array.len
                                          (local.tee $9
                                            (struct.get $values 0 (ref.cast (ref $values) (local.get $1)))
                                          )
                                        )
                                        (i32.const 1)
                                      )
                                    )
                                    (br $block13 (array.get $vector (local.get $9) (i32.const 0)))
                                  )
                                )
                                (local.get $1)
                              )
                            )
                            (local.set $3
                              (block $block14
                                (result eqref)
                                (br_if $block (ref.is_null (local.tee $11 (global.get $g63))))
                                (if
                                  (ref.test
                                    (ref $values)
                                    (local.tee $3
                                      (call $primitive63
                                        (struct.get $closure 1 (local.get $11))
                                        (array.new_fixed $vector 2 (local.get $3) (local.get $4))
                                        (ref.null none)
                                      )
                                    )
                                  )
                                  (then
                                    (br_if $block9
                                      (i32.ne
                                        (array.len
                                          (local.tee $9
                                            (struct.get $values 0 (ref.cast (ref $values) (local.get $3)))
                                          )
                                        )
                                        (i32.const 1)
                                      )
                                    )
                                    (br $block14 (array.get $vector (local.get $9) (i32.const 0)))
                                  )
                                )
                                (local.get $3)
                              )
                            )
                            (local.set $6
                              (block $block15
                                (result eqref)
                                (br_if $block
                                  (i32.or
                                    (ref.is_null (local.get $6))
                                    (ref.eq (local.get $6) (global.get $uninitialized))
                                  )
                                )
                                (if
                                  (ref.test (ref $values) (local.get $6))
                                  (then
                                    (br_if $block9
                                      (i32.ne
                                        (array.len
                                          (local.tee $9
                                            (struct.get $values 0 (ref.cast (ref $values) (local.get $6)))
                                          )
                                        )
                                        (i32.const 1)
                                      )
                                    )
                                    (br $block15 (array.get $vector (local.get $9) (i32.const 0)))
                                  )
                                )
                                (local.get $6)
                              )
                            )
                            (br $block25
                              (block $block24
                                (result (ref $atom))
                                (br_if $block
                                  (i32.or
                                    (ref.is_null
                                      (local.tee $3
                                        (block $block16
                                          (result eqref)
                                          (br_if $block (ref.is_null (local.tee $11 (global.get $g63))))
                                          (if
                                            (ref.test
                                              (ref $values)
                                              (local.tee $3
                                                (call $primitive63
                                                  (struct.get $closure 1 (local.get $11))
                                                  (array.new_fixed $vector 2 (local.get $3) (local.get $6))
                                                  (ref.null none)
                                                )
                                              )
                                            )
                                            (then
                                              (br_if $block9
                                                (i32.ne
                                                  (array.len
                                                    (local.tee $9
                                                      (struct.get $values 0
                                                        (ref.cast (ref $values) (local.get $3))
                                                      )
                                                    )
                                                  )
                                                  (i32.const 1)
                                                )
                                              )
                                              (br $block16 (array.get $vector (local.get $9) (i32.const 0)))
                                            )
                                          )
                                          (local.get $3)
                                        )
                                      )
                                    )
                                    (ref.eq (local.get $3) (global.get $uninitialized))
                                  )
                                )
                                (block $block17
                                  (local.set $0
                                    (block $block18
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
                                          (br_if $block17
                                            (i32.ne
                                              (array.len
                                                (local.tee $9
                                                  (struct.get $values 0
                                                    (ref.cast (ref $values) (local.get $0))
                                                  )
                                                )
                                              )
                                              (i32.const 1)
                                            )
                                          )
                                          (br $block18 (array.get $vector (local.get $9) (i32.const 0)))
                                        )
                                      )
                                      (local.get $0)
                                    )
                                  )
                                  (br_if $block
                                    (i32.or
                                      (ref.is_null (local.get $5))
                                      (ref.eq (local.get $5) (global.get $uninitialized))
                                    )
                                  )
                                  (local.set $0
                                    (block $block19
                                      (result eqref)
                                      (br_if $block (ref.is_null (local.tee $11 (global.get $g63))))
                                      (if
                                        (ref.test
                                          (ref $values)
                                          (local.tee $0
                                            (call $primitive63
                                              (struct.get $closure 1 (local.get $11))
                                              (array.new_fixed $vector 2 (local.get $0) (local.get $5))
                                              (ref.null none)
                                            )
                                          )
                                        )
                                        (then
                                          (br_if $block17
                                            (i32.ne
                                              (array.len
                                                (local.tee $9
                                                  (struct.get $values 0
                                                    (ref.cast (ref $values) (local.get $0))
                                                  )
                                                )
                                              )
                                              (i32.const 1)
                                            )
                                          )
                                          (br $block19 (array.get $vector (local.get $9) (i32.const 0)))
                                        )
                                      )
                                      (local.get $0)
                                    )
                                  )
                                  (local.set $5
                                    (block $block20
                                      (result eqref)
                                      (br_if $block
                                        (i32.or
                                          (ref.is_null (local.get $7))
                                          (ref.eq (local.get $7) (global.get $uninitialized))
                                        )
                                      )
                                      (if
                                        (ref.test (ref $values) (local.get $7))
                                        (then
                                          (br_if $block17
                                            (i32.ne
                                              (array.len
                                                (local.tee $9
                                                  (struct.get $values 0
                                                    (ref.cast (ref $values) (local.get $7))
                                                  )
                                                )
                                              )
                                              (i32.const 1)
                                            )
                                          )
                                          (br $block20 (array.get $vector (local.get $9) (i32.const 0)))
                                        )
                                      )
                                      (local.get $7)
                                    )
                                  )
                                  (br $block24
                                    (if
                                      (result (ref $atom))
                                      (block $block22
                                        (result i32)
                                        (drop
                                          (br_if $block22
                                            (i32.const 1)
                                            (ref.eq
                                              (local.get $3)
                                              (local.tee $0
                                                (block $block21
                                                  (result eqref)
                                                  (br_if $block
                                                    (ref.is_null (local.tee $11 (global.get $g63)))
                                                  )
                                                  (if
                                                    (ref.test
                                                      (ref $values)
                                                      (local.tee $0
                                                        (call $primitive63
                                                          (struct.get $closure 1 (local.get $11))
                                                          (array.new_fixed $vector 2
                                                            (local.get $0)
                                                            (local.get $5)
                                                          )
                                                          (ref.null none)
                                                        )
                                                      )
                                                    )
                                                    (then
                                                      (br_if $block17
                                                        (i32.ne
                                                          (array.len
                                                            (local.tee $9
                                                              (struct.get $values 0
                                                                (ref.cast (ref $values) (local.get $0))
                                                              )
                                                            )
                                                          )
                                                          (i32.const 1)
                                                        )
                                                      )
                                                      (br $block21
                                                        (array.get $vector (local.get $9) (i32.const 0))
                                                      )
                                                    )
                                                  )
                                                  (local.get $0)
                                                )
                                              )
                                            )
                                          )
                                        )
                                        (if
                                          (i32.and
                                            (if
                                              (result i32)
                                              (ref.test (ref $atom) (local.get $3))
                                              (then
                                                (i32.lt_s
                                                  (struct.get $atom 0 (ref.cast (ref $atom) (local.get $3)))
                                                  (i32.const 0)
                                                )
                                              )
                                              (else (i32.const 0))
                                            )
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
                                          )
                                          (then
                                            (br $block22
                                              (i32.eq
                                                (struct.get $atom 0 (ref.cast (ref $atom) (local.get $3)))
                                                (struct.get $atom 0 (ref.cast (ref $atom) (local.get $0)))
                                              )
                                            )
                                          )
                                        )
                                        (i32.const 0)
                                      )
                                      (then
                                        (local.set $12 (ref.i31 (i32.const 1)))
                                        (local.set $0
                                          (if
                                            (result eqref)
                                            (ref.test
                                              (ref i31)
                                              (local.tee $0
                                                (block $block23
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
                                                      (br_if $block17
                                                        (i32.ne
                                                          (array.len
                                                            (local.tee $9
                                                              (struct.get $values 0
                                                                (ref.cast (ref $values) (local.get $1))
                                                              )
                                                            )
                                                          )
                                                          (i32.const 1)
                                                        )
                                                      )
                                                      (br $block23
                                                        (array.get $vector (local.get $9) (i32.const 0))
                                                      )
                                                    )
                                                  )
                                                  (local.get $1)
                                                )
                                              )
                                            )
                                            (then
                                              (if
                                                (result eqref)
                                                (i32.le_u
                                                  (i32.add
                                                    (local.tee $14
                                                      (i32.add
                                                        (i31.get_s (ref.cast (ref i31) (local.get $0)))
                                                        (i32.const 1)
                                                      )
                                                    )
                                                    (i32.const 1073741824)
                                                  )
                                                  (i32.const 2147483647)
                                                )
                                                (then (ref.i31 (local.get $14)))
                                                (else (call $cold.checked_add (local.get $0) (local.get $12)))
                                              )
                                            )
                                            (else (call $cold.checked_add (local.get $0) (local.get $12)))
                                          )
                                        )
                                        (br_if $block
                                          (ref.eq
                                            (local.tee $13
                                              (struct.get $cell 0 (ref.cast (ref $cell) (local.get $8)))
                                            )
                                            (global.get $uninitialized)
                                          )
                                        )
                                        (return_call $function178
                                          (struct.get $closure 1 (ref.cast (ref $closure) (local.get $13)))
                                          (local.get $0)
                                          (local.get $2)
                                        )
                                      )
                                      (else
                                        (br_if $block
                                          (i32.or
                                            (ref.is_null (local.get $3))
                                            (ref.eq (local.get $3) (global.get $uninitialized))
                                          )
                                        )
                                        (select
                                          (result (ref $atom))
                                          (global.get $literal15)
                                          (global.get $literal11)
                                          (ref.eq (local.get $3) (global.get $false))
                                        )
                                      )
                                    )
                                  )
                                )
                                (br $block9)
                              )
                            )
                          )
                          (else
                            (br_if $block
                              (i32.or
                                (ref.is_null (local.get $3))
                                (ref.eq (local.get $3) (global.get $uninitialized))
                              )
                            )
                            (select
                              (result (ref $atom))
                              (global.get $literal15)
                              (global.get $literal11)
                              (ref.eq (local.get $3) (global.get $false))
                            )
                          )
                        )
                      )
                    )
                    (br $block1)
                  )
                )
              )
              (else (global.get $literal13))
            )
          )
        )
        (global.set $error_code (i32.const 6))
        (local.set $15 (i32.load (i32.const 1062312)))
        (br $block26 (i32.load (i32.const 1062352)))
      )
      (global.set $error_code (i32.const 5))
      (local.set $15 (i32.load (i32.const 1062308)))
      (i32.load (i32.const 1062348))
    )
  )
  (global.set $__stack_pointer (local.tee $14 (i32.sub (global.get $__stack_pointer) (i32.const 32))))
  (call $_RNvMNtCsi9YzqDQQz2q_5alloc6stringNtB2_6String15from_utf8_lossy
    (local.tee $17 (i32.add (local.get $14) (i32.const 12)))
    (local.get $16)
    (local.get $15)
  )
  (i64.store offset=24 (local.get $14) (i64.or (i64.extend_i32_u (local.get $17)) (i64.const 103079215104)))
  (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio7__eprint (i32.add (local.get $14) (i32.const 24)))
  (local.set $15 (i32.load offset=16 (local.get $14)))
  (if (i32.gt_s (i32.load offset=12 (local.get $14)) (i32.const 0)) (then (call $dlfree (local.get $15))))
  (call $_RNvNtCset5xJoy1xWQ_3std2rt7cleanup)
  (call $__imported_wasi_snapshot_preview1_proc_exit (i32.const 1))
  (unreachable)
)
