;; Exact original optimized function $function133, import-inclusive index 159.
;; Full module and referenced definitions are retained in raw-artifacts.tar.xz.
(func $function133
  (type $26)
  (param $0 (ref $vector))
  (param $1 eqref)
  (param $2 nullref)
  (result eqref)
  (local $3 (ref $vector))
  (local $4 (ref $vector))
  (local $5 eqref)
  (local $6 eqref)
  (local $7 eqref)
  (local $8 (ref i31))
  (local $9 (ref null $closure))
  (local $10 (ref struct))
  (local $11 (ref null $vector))
  (local $12 (ref $closure))
  (local $13 i32)
  (local $14 i32)
  (local $15 i32)
  (local $16 i32)
  (local.set $15
    (block $block1
      (result i32)
      (block $block2
        (block $block
          (br_if $block
            (i32.or (ref.is_null (local.get $1)) (ref.eq (local.get $1) (global.get $uninitialized)))
          )
          (br_if $block (ref.is_null (local.tee $9 (global.get $g146))))
          (drop (ref.as_non_null (local.get $9)))
          (if
            (i32.or
              (i32.ne
                (local.tee $13 (array.len (local.tee $4 (array.new_fixed $vector 1 (local.get $1)))))
                (i32.const 1)
              )
              (i32.eqz (local.get $13))
            )
            (then
              (global.set $error_code (i32.const 4))
              (local.set $14 (i32.load (i32.const 1062304)))
              (br $block1 (i32.load (i32.const 1062344)))
            )
          )
          (local.set $7
            (if
              (result eqref)
              (ref.eq (array.get $vector (local.get $4) (i32.const 0)) (global.get $eof))
              (then
                (local.set $5
                  (block $block3
                    (result eqref)
                    (br_if $block
                      (i32.or
                        (ref.is_null (local.tee $1 (array.get $vector (local.get $0) (i32.const 0))))
                        (ref.eq (local.get $1) (global.get $uninitialized))
                      )
                    )
                    (if
                      (ref.test (ref $values) (local.get $1))
                      (then
                        (br_if $block2
                          (i32.ne
                            (array.len
                              (local.tee $3 (struct.get $values 0 (ref.cast (ref $values) (local.get $1))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block3 (array.get $vector (local.get $3) (i32.const 0)))
                      )
                    )
                    (local.get $1)
                  )
                )
                (local.set $6
                  (block $block4
                    (result eqref)
                    (br_if $block
                      (i32.or
                        (ref.is_null (local.tee $1 (array.get $vector (local.get $0) (i32.const 1))))
                        (ref.eq (local.get $1) (global.get $uninitialized))
                      )
                    )
                    (if
                      (ref.test (ref $values) (local.get $1))
                      (then
                        (br_if $block2
                          (i32.ne
                            (array.len
                              (local.tee $3 (struct.get $values 0 (ref.cast (ref $values) (local.get $1))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block4 (array.get $vector (local.get $3) (i32.const 0)))
                      )
                    )
                    (local.get $1)
                  )
                )
                (local.set $1
                  (block $block5
                    (result eqref)
                    (br_if $block
                      (i32.or
                        (ref.is_null (local.tee $1 (array.get $vector (local.get $0) (i32.const 2))))
                        (ref.eq (local.get $1) (global.get $uninitialized))
                      )
                    )
                    (if
                      (ref.test (ref $values) (local.get $1))
                      (then
                        (br_if $block2
                          (i32.ne
                            (array.len
                              (local.tee $3 (struct.get $values 0 (ref.cast (ref $values) (local.get $1))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block5 (array.get $vector (local.get $3) (i32.const 0)))
                      )
                    )
                    (local.get $1)
                  )
                )
                (br_if $block (ref.is_null (local.tee $9 (global.get $g182))))
                (return_call_ref $call
                  (struct.get $closure 1 (local.tee $12 (ref.as_non_null (local.get $9))))
                  (array.new_fixed $vector 3 (local.get $5) (local.get $6) (local.get $1))
                  (local.get $2)
                  (struct.get $closure 0 (local.get $12))
                )
              )
              (else
                (br_if $block
                  (local.tee $13
                    (i32.or (ref.is_null (local.get $1)) (ref.eq (local.get $1) (global.get $uninitialized)))
                  )
                )
                (br_if $block (ref.is_null (local.tee $9 (global.get $g81))))
                (drop (ref.as_non_null (local.get $9)))
                (if
                  (result eqref)
                  (ref.eq
                    (call $builtin:char=?
                      (array.new_fixed $vector 2 (local.get $1) (struct.new $atom (i32.const 288)))
                    )
                    (global.get $false)
                  )
                  (then
                    (br_if $block (local.get $13))
                    (br_if $block (ref.is_null (local.tee $9 (global.get $g81))))
                    (drop (ref.as_non_null (local.get $9)))
                    (if
                      (result eqref)
                      (ref.eq
                        (call $builtin:char=?
                          (array.new_fixed $vector 2 (local.get $1) (struct.new $atom (i32.const 266)))
                        )
                        (global.get $false)
                      )
                      (then
                        (return_call $function133
                          (array.new_fixed $vector 5
                            (block $block6
                              (result eqref)
                              (br_if $block
                                (i32.or
                                  (ref.is_null
                                    (local.tee $1 (array.get $vector (local.get $0) (i32.const 0)))
                                  )
                                  (ref.eq (local.get $1) (global.get $uninitialized))
                                )
                              )
                              (if
                                (ref.test (ref $values) (local.get $1))
                                (then
                                  (br_if $block2
                                    (i32.ne
                                      (array.len
                                        (local.tee $3
                                          (struct.get $values 0 (ref.cast (ref $values) (local.get $1)))
                                        )
                                      )
                                      (i32.const 1)
                                    )
                                  )
                                  (br $block6 (array.get $vector (local.get $3) (i32.const 0)))
                                )
                              )
                              (local.get $1)
                            )
                            (block $block9
                              (result eqref)
                              (if
                                (ref.test
                                  (ref $values)
                                  (local.tee $1
                                    (if
                                      (result eqref)
                                      (ref.eq
                                        (block $block7
                                          (result eqref)
                                          (br_if $block
                                            (i32.or
                                              (ref.is_null
                                                (local.tee $1
                                                  (array.get $vector (local.get $0) (i32.const 4))
                                                )
                                              )
                                              (ref.eq (local.get $1) (global.get $uninitialized))
                                            )
                                          )
                                          (if
                                            (ref.test (ref $values) (local.get $1))
                                            (then
                                              (br_if $block2
                                                (i32.ne
                                                  (array.len
                                                    (local.tee $3
                                                      (struct.get $values 0
                                                        (ref.cast (ref $values) (local.get $1))
                                                      )
                                                    )
                                                  )
                                                  (i32.const 1)
                                                )
                                              )
                                              (br $block7 (array.get $vector (local.get $3) (i32.const 0)))
                                            )
                                          )
                                          (local.get $1)
                                        )
                                        (global.get $false)
                                      )
                                      (then
                                        (local.set $8 (ref.i31 (i32.const 1)))
                                        (if
                                          (result eqref)
                                          (ref.test
                                            (ref i31)
                                            (local.tee $1
                                              (block $block8
                                                (result eqref)
                                                (br_if $block
                                                  (i32.or
                                                    (ref.is_null
                                                      (local.tee $1
                                                        (array.get $vector (local.get $0) (i32.const 1))
                                                      )
                                                    )
                                                    (ref.eq (local.get $1) (global.get $uninitialized))
                                                  )
                                                )
                                                (if
                                                  (ref.test (ref $values) (local.get $1))
                                                  (then
                                                    (br_if $block2
                                                      (i32.ne
                                                        (array.len
                                                          (local.tee $3
                                                            (struct.get $values 0
                                                              (ref.cast (ref $values) (local.get $1))
                                                            )
                                                          )
                                                        )
                                                        (i32.const 1)
                                                      )
                                                    )
                                                    (br $block8
                                                      (array.get $vector (local.get $3) (i32.const 0))
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
                                                  (local.tee $13
                                                    (i32.add
                                                      (i31.get_s (ref.cast (ref i31) (local.get $1)))
                                                      (i32.const 1)
                                                    )
                                                  )
                                                  (i32.const 1073741824)
                                                )
                                                (i32.const 2147483647)
                                              )
                                              (then (ref.i31 (local.get $13)))
                                              (else (call $cold.checked_add (local.get $1) (local.get $8)))
                                            )
                                          )
                                          (else (call $cold.checked_add (local.get $1) (local.get $8)))
                                        )
                                      )
                                      (else
                                        (br_if $block
                                          (i32.or
                                            (ref.is_null
                                              (local.tee $1 (array.get $vector (local.get $0) (i32.const 1)))
                                            )
                                            (ref.eq (local.get $1) (global.get $uninitialized))
                                          )
                                        )
                                        (local.get $1)
                                      )
                                    )
                                  )
                                )
                                (then
                                  (br_if $block2
                                    (i32.ne
                                      (array.len
                                        (local.tee $3
                                          (struct.get $values 0 (ref.cast (ref $values) (local.get $1)))
                                        )
                                      )
                                      (i32.const 1)
                                    )
                                  )
                                  (br $block9 (array.get $vector (local.get $3) (i32.const 0)))
                                )
                              )
                              (local.get $1)
                            )
                            (block
                              (result eqref)
                              (local.set $8 (ref.i31 (i32.const 1)))
                              (if
                                (result eqref)
                                (ref.test
                                  (ref i31)
                                  (local.tee $1
                                    (block $block10
                                      (result eqref)
                                      (br_if $block
                                        (i32.or
                                          (ref.is_null
                                            (local.tee $1 (array.get $vector (local.get $0) (i32.const 2)))
                                          )
                                          (ref.eq (local.get $1) (global.get $uninitialized))
                                        )
                                      )
                                      (if
                                        (ref.test (ref $values) (local.get $1))
                                        (then
                                          (br_if $block2
                                            (i32.ne
                                              (array.len
                                                (local.tee $3
                                                  (struct.get $values 0
                                                    (ref.cast (ref $values) (local.get $1))
                                                  )
                                                )
                                              )
                                              (i32.const 1)
                                            )
                                          )
                                          (br $block10 (array.get $vector (local.get $3) (i32.const 0)))
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
                                        (local.tee $13
                                          (i32.add
                                            (i31.get_s (ref.cast (ref i31) (local.get $1)))
                                            (i32.const 1)
                                          )
                                        )
                                        (i32.const 1073741824)
                                      )
                                      (i32.const 2147483647)
                                    )
                                    (then (ref.i31 (local.get $13)))
                                    (else (call $cold.checked_add (local.get $1) (local.get $8)))
                                  )
                                )
                                (else (call $cold.checked_add (local.get $1) (local.get $8)))
                              )
                            )
                            (block
                              (result eqref)
                              (local.set $1
                                (block $block11
                                  (result eqref)
                                  (br_if $block
                                    (ref.eq
                                      (local.tee $10
                                        (struct.get $cell 0
                                          (ref.cast
                                            (ref $cell)
                                            (array.get $vector (local.get $0) (i32.const 3))
                                          )
                                        )
                                      )
                                      (global.get $uninitialized)
                                    )
                                  )
                                  (br_if $block
                                    (i32.or
                                      (ref.is_null
                                        (local.tee $1
                                          (array.get $vector
                                            (local.tee $11
                                              (struct.get $closure 1
                                                (ref.cast (ref $closure) (local.get $10))
                                              )
                                            )
                                            (i32.const 1)
                                          )
                                        )
                                      )
                                      (ref.eq (local.get $1) (global.get $uninitialized))
                                    )
                                  )
                                  (if
                                    (ref.test (ref $values) (local.get $1))
                                    (then
                                      (br_if $block2
                                        (i32.ne
                                          (array.len
                                            (local.tee $3
                                              (struct.get $values 0 (ref.cast (ref $values) (local.get $1)))
                                            )
                                          )
                                          (i32.const 1)
                                        )
                                      )
                                      (br $block11 (array.get $vector (local.get $3) (i32.const 0)))
                                    )
                                  )
                                  (local.get $1)
                                )
                              )
                              (local.set $1
                                (block $block12
                                  (result eqref)
                                  (br_if $block (ref.is_null (local.tee $9 (global.get $g137))))
                                  (drop (struct.get $closure 1 (local.get $9)))
                                  (local.set $1
                                    (call $abi_take
                                      (call $snail:read-char
                                        (local.tee $13
                                          (call $abi_root (array.new_fixed $vector 1 (local.get $1)))
                                        )
                                      )
                                    )
                                  )
                                  (if (i32.ge_u (local.get $13) (global.get $abi_used)) (then (unreachable)))
                                  (if
                                    (i32.ne
                                      (array.get $text (global.get $abi_links) (local.get $13))
                                      (i32.const -1)
                                    )
                                    (then (unreachable))
                                  )
                                  (drop (table.get $abi_roots (local.get $13)))
                                  (table.set $abi_roots (local.get $13) (ref.null none))
                                  (array.set $text
                                    (global.get $abi_links)
                                    (local.get $13)
                                    (global.get $abi_free)
                                  )
                                  (global.set $abi_free (local.get $13))
                                  (global.set $abi_live (i32.sub (global.get $abi_live) (i32.const 1)))
                                  (if
                                    (ref.test (ref $values) (local.get $1))
                                    (then
                                      (br_if $block2
                                        (i32.ne
                                          (array.len
                                            (local.tee $3
                                              (struct.get $values 0 (ref.cast (ref $values) (local.get $1)))
                                            )
                                          )
                                          (i32.const 1)
                                        )
                                      )
                                      (br $block12 (array.get $vector (local.get $3) (i32.const 0)))
                                    )
                                  )
                                  (local.get $1)
                                )
                              )
                              (array.get $vector (local.get $11) (i32.const 0))
                            )
                            (global.get $true)
                          )
                          (local.get $1)
                          (local.get $2)
                        )
                      )
                      (else
                        (local.set $8 (ref.i31 (i32.const 1)))
                        (local.set $6
                          (if
                            (result eqref)
                            (ref.test
                              (ref i31)
                              (local.tee $1
                                (block $block13
                                  (result eqref)
                                  (br_if $block
                                    (i32.or
                                      (ref.is_null
                                        (local.tee $1 (array.get $vector (local.get $0) (i32.const 0)))
                                      )
                                      (ref.eq (local.get $1) (global.get $uninitialized))
                                    )
                                  )
                                  (if
                                    (ref.test (ref $values) (local.get $1))
                                    (then
                                      (br_if $block2
                                        (i32.ne
                                          (array.len
                                            (local.tee $3
                                              (struct.get $values 0 (ref.cast (ref $values) (local.get $1)))
                                            )
                                          )
                                          (i32.const 1)
                                        )
                                      )
                                      (br $block13 (array.get $vector (local.get $3) (i32.const 0)))
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
                                    (local.tee $13
                                      (i32.add (i31.get_s (ref.cast (ref i31) (local.get $1))) (i32.const 1))
                                    )
                                    (i32.const 1073741824)
                                  )
                                  (i32.const 2147483647)
                                )
                                (then (ref.i31 (local.get $13)))
                                (else (call $cold.checked_add (local.get $1) (local.get $8)))
                              )
                            )
                            (else (call $cold.checked_add (local.get $1) (local.get $8)))
                          )
                        )
                        (local.set $1
                          (block $block14
                            (result eqref)
                            (br_if $block
                              (i32.or
                                (ref.is_null (local.tee $1 (array.get $vector (local.get $0) (i32.const 1))))
                                (ref.eq (local.get $1) (global.get $uninitialized))
                              )
                            )
                            (if
                              (ref.test (ref $values) (local.get $1))
                              (then
                                (br_if $block2
                                  (i32.ne
                                    (array.len
                                      (local.tee $3
                                        (struct.get $values 0 (ref.cast (ref $values) (local.get $1)))
                                      )
                                    )
                                    (i32.const 1)
                                  )
                                )
                                (br $block14 (array.get $vector (local.get $3) (i32.const 0)))
                              )
                            )
                            (local.get $1)
                          )
                        )
                        (if
                          (result eqref)
                          (ref.test
                            (ref i31)
                            (local.tee $5
                              (block $block15
                                (result eqref)
                                (br_if $block
                                  (i32.or
                                    (ref.is_null
                                      (local.tee $5 (array.get $vector (local.get $0) (i32.const 2)))
                                    )
                                    (ref.eq (local.get $5) (global.get $uninitialized))
                                  )
                                )
                                (if
                                  (ref.test (ref $values) (local.get $5))
                                  (then
                                    (br_if $block2
                                      (i32.ne
                                        (array.len
                                          (local.tee $3
                                            (struct.get $values 0 (ref.cast (ref $values) (local.get $5)))
                                          )
                                        )
                                        (i32.const 1)
                                      )
                                    )
                                    (br $block15 (array.get $vector (local.get $3) (i32.const 0)))
                                  )
                                )
                                (local.get $5)
                              )
                            )
                          )
                          (then
                            (if
                              (result eqref)
                              (i32.le_u
                                (i32.add
                                  (local.tee $13
                                    (i32.add (i31.get_s (ref.cast (ref i31) (local.get $5))) (i32.const 1))
                                  )
                                  (i32.const 1073741824)
                                )
                                (i32.const 2147483647)
                              )
                              (then (ref.i31 (local.get $13)))
                              (else (call $cold.checked_add (local.get $5) (local.get $8)))
                            )
                          )
                          (else (call $cold.checked_add (local.get $5) (local.get $8)))
                        )
                      )
                    )
                  )
                  (else
                    (local.set $6
                      (block $block16
                        (result eqref)
                        (br_if $block
                          (i32.or
                            (ref.is_null (local.tee $1 (array.get $vector (local.get $0) (i32.const 0))))
                            (ref.eq (local.get $1) (global.get $uninitialized))
                          )
                        )
                        (if
                          (ref.test (ref $values) (local.get $1))
                          (then
                            (br_if $block2
                              (i32.ne
                                (array.len
                                  (local.tee $3
                                    (struct.get $values 0 (ref.cast (ref $values) (local.get $1)))
                                  )
                                )
                                (i32.const 1)
                              )
                            )
                            (br $block16 (array.get $vector (local.get $3) (i32.const 0)))
                          )
                        )
                        (local.get $1)
                      )
                    )
                    (local.set $1
                      (block $block17
                        (result eqref)
                        (br_if $block
                          (i32.or
                            (ref.is_null (local.tee $1 (array.get $vector (local.get $0) (i32.const 1))))
                            (ref.eq (local.get $1) (global.get $uninitialized))
                          )
                        )
                        (if
                          (ref.test (ref $values) (local.get $1))
                          (then
                            (br_if $block2
                              (i32.ne
                                (array.len
                                  (local.tee $3
                                    (struct.get $values 0 (ref.cast (ref $values) (local.get $1)))
                                  )
                                )
                                (i32.const 1)
                              )
                            )
                            (br $block17 (array.get $vector (local.get $3) (i32.const 0)))
                          )
                        )
                        (local.get $1)
                      )
                    )
                    (local.set $8 (ref.i31 (i32.const 1)))
                    (if
                      (result eqref)
                      (ref.test
                        (ref i31)
                        (local.tee $5
                          (block $block18
                            (result eqref)
                            (br_if $block
                              (i32.or
                                (ref.is_null (local.tee $5 (array.get $vector (local.get $0) (i32.const 2))))
                                (ref.eq (local.get $5) (global.get $uninitialized))
                              )
                            )
                            (if
                              (ref.test (ref $values) (local.get $5))
                              (then
                                (br_if $block2
                                  (i32.ne
                                    (array.len
                                      (local.tee $3
                                        (struct.get $values 0 (ref.cast (ref $values) (local.get $5)))
                                      )
                                    )
                                    (i32.const 1)
                                  )
                                )
                                (br $block18 (array.get $vector (local.get $3) (i32.const 0)))
                              )
                            )
                            (local.get $5)
                          )
                        )
                      )
                      (then
                        (if
                          (result eqref)
                          (i32.le_u
                            (i32.add
                              (local.tee $13
                                (i32.add (i31.get_s (ref.cast (ref i31) (local.get $5))) (i32.const 1))
                              )
                              (i32.const 1073741824)
                            )
                            (i32.const 2147483647)
                          )
                          (then (ref.i31 (local.get $13)))
                          (else (call $cold.checked_add (local.get $5) (local.get $8)))
                        )
                      )
                      (else (call $cold.checked_add (local.get $5) (local.get $8)))
                    )
                  )
                )
              )
            )
          )
          (local.set $5
            (block $block19
              (result eqref)
              (br_if $block
                (ref.eq
                  (local.tee $10
                    (struct.get $cell 0
                      (ref.cast (ref $cell) (array.get $vector (local.get $0) (i32.const 3)))
                    )
                  )
                  (global.get $uninitialized)
                )
              )
              (br_if $block
                (i32.or
                  (ref.is_null
                    (local.tee $5
                      (array.get $vector
                        (local.tee $11 (struct.get $closure 1 (ref.cast (ref $closure) (local.get $10))))
                        (i32.const 1)
                      )
                    )
                  )
                  (ref.eq (local.get $5) (global.get $uninitialized))
                )
              )
              (if
                (ref.test (ref $values) (local.get $5))
                (then
                  (br_if $block2
                    (i32.ne
                      (array.len
                        (local.tee $3 (struct.get $values 0 (ref.cast (ref $values) (local.get $5))))
                      )
                      (i32.const 1)
                    )
                  )
                  (br $block19 (array.get $vector (local.get $3) (i32.const 0)))
                )
              )
              (local.get $5)
            )
          )
          (local.set $5
            (block $block20
              (result eqref)
              (br_if $block (ref.is_null (local.tee $9 (global.get $g137))))
              (drop (struct.get $closure 1 (local.get $9)))
              (local.set $5
                (call $abi_take
                  (call $snail:read-char
                    (local.tee $13 (call $abi_root (array.new_fixed $vector 1 (local.get $5))))
                  )
                )
              )
              (if (i32.ge_u (local.get $13) (global.get $abi_used)) (then (unreachable)))
              (if
                (i32.ne (array.get $text (global.get $abi_links) (local.get $13)) (i32.const -1))
                (then (unreachable))
              )
              (drop (table.get $abi_roots (local.get $13)))
              (table.set $abi_roots (local.get $13) (ref.null none))
              (array.set $text (global.get $abi_links) (local.get $13) (global.get $abi_free))
              (global.set $abi_free (local.get $13))
              (global.set $abi_live (i32.sub (global.get $abi_live) (i32.const 1)))
              (if
                (ref.test (ref $values) (local.get $5))
                (then
                  (br_if $block2
                    (i32.ne
                      (array.len
                        (local.tee $3 (struct.get $values 0 (ref.cast (ref $values) (local.get $5))))
                      )
                      (i32.const 1)
                    )
                  )
                  (br $block20 (array.get $vector (local.get $3) (i32.const 0)))
                )
              )
              (local.get $5)
            )
          )
          (return_call $function133
            (array.new_fixed $vector 5
              (local.get $6)
              (local.get $1)
              (local.get $7)
              (array.get $vector (local.get $11) (i32.const 0))
              (global.get $false)
            )
            (local.get $5)
            (local.get $2)
          )
        )
        (global.set $error_code (i32.const 6))
        (local.set $14 (i32.load (i32.const 1062312)))
        (br $block1 (i32.load (i32.const 1062352)))
      )
      (global.set $error_code (i32.const 5))
      (local.set $14 (i32.load (i32.const 1062308)))
      (i32.load (i32.const 1062348))
    )
  )
  (global.set $__stack_pointer (local.tee $13 (i32.sub (global.get $__stack_pointer) (i32.const 32))))
  (call $_RNvMNtCsi9YzqDQQz2q_5alloc6stringNtB2_6String15from_utf8_lossy
    (local.tee $16 (i32.add (local.get $13) (i32.const 12)))
    (local.get $15)
    (local.get $14)
  )
  (i64.store offset=24 (local.get $13) (i64.or (i64.extend_i32_u (local.get $16)) (i64.const 103079215104)))
  (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio7__eprint (i32.add (local.get $13) (i32.const 24)))
  (local.set $14 (i32.load offset=16 (local.get $13)))
  (if (i32.gt_s (i32.load offset=12 (local.get $13)) (i32.const 0)) (then (call $dlfree (local.get $14))))
  (call $_RNvNtCset5xJoy1xWQ_3std2rt7cleanup)
  (call $__imported_wasi_snapshot_preview1_proc_exit (i32.const 1))
  (unreachable)
)
