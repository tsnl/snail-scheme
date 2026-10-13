;; Extracted from final optimized Wasm; dependencies outside this projection are retained in the raw archive.
(type $atom
  (struct
    (field i32)))

(type $binding_cell0
  (struct
    (field
      (mut i32))
    (field
      (mut
        (ref null $closure)))))

(type $closure
  (struct
    (field
      (ref $call))
    (field structref)))

(type $elements:bytevector
  (array
    (mut
      (ref $bytevector))))

(type $elements:closure
  (array
    (mut
      (ref $closure))))

(type $elements:complex
  (array
    (mut
      (ref $complex))))

(type $elements:f32
  (array
    (mut f32)))

(type $elements:integer
  (array
    (mut i64)))

(type $elements:pair
  (array
    (mut
      (ref $pair))))

(type $elements:real
  (array
    (mut f64)))

(type $elements:record
  (array
    (mut
      (ref none))))

(type $elements:string
  (array
    (mut
      (ref $text_object))))

(type $elements:vector
  (array
    (mut
      (ref $vector_object))))

(type $environment162
  (struct
    (field
      (ref $binding_cell0))))

(type $environment61
  (struct
    (field i64)
    (field i64)))

(type $integer
  (struct
    (field i64)))

(type $pair
  (struct
    (field
      (mut eqref))
    (field
      (mut eqref))))

(type $slots
  (array
    (mut eqref)))

(type $text
  (array
    (mut i32)))

(type $values
  (struct
    (field eqref)))

(type $vector_object
  (struct
    (field i32)
    (field
      (ref array))
    (field i32)))

(func $function62
  (type $29)
  (param $0 eqref)
  (param $1
    (ref struct))
  (result
    (ref $vector_object))
  (local $2 i32)
  (local $3 i32)
  (local $4 i32)
  (local $5 i32)
  (local $6 i64)
  (local $7 i64)
  (local $8
    (ref $vector_object))
  (local $9
    (ref $vector_object))
  (local $10
    (ref eq))
  (local $11
    (ref eq))
  (local.set $8
    (ref.cast
      (ref $vector_object)
      (local.get $0)))
  (local.set $3
    (block $block13
      (result i32)
      (block $block16
        (block $block
          (br_if $block
            (ref.eq
              (local.get $1)
              (global.get $uninitialized)))
          (block $block1
            (local.set $7
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
                          (local.tee $0
                            (if
                              (result eqref)
                              (if
                                (result i32)
                                (ref.eq
                                  (local.get $1)
                                  (global.get $nil))
                                (then
                                  (i32.const 1))
                                (else
                                  (drop
                                    (if
                                      (result i32)
                                      (ref.test
                                        (ref $atom)
                                        (local.get $1))
                                      (then
                                        (i32.lt_s
                                          (struct.get $atom 0
                                            (ref.cast
                                              (ref $atom)
                                              (local.get $1)))
                                          (i32.const 0)))
                                      (else
                                        (i32.const 0))))
                                  (i32.const 0)))
                              (then
                                (ref.i31
                                  (i32.const 0)))
                              (else
                                (br_if $block
                                  (ref.eq
                                    (local.get $1)
                                    (global.get $uninitialized)))
                                (struct.get $pair 0
                                  (ref.cast
                                    (ref $pair)
                                    (local.get $1)))))))
                        (then
                          (br_if $block1
                            (i32.ne
                              (if
                                (result i32)
                                (ref.test
                                  (ref $vector_object)
                                  (local.tee $0
                                    (struct.get $values 0
                                      (ref.cast
                                        (ref $values)
                                        (local.get $0)))))
                                (then
                                  (struct.get $vector_object 2
                                    (ref.cast
                                      (ref $vector_object)
                                      (local.get $0))))
                                (else
                                  (array.len
                                    (ref.cast
                                      (ref $slots)
                                      (local.get $0)))))
                              (i32.const 1)))
                          (br $block2
                            (if
                              (result eqref)
                              (ref.test
                                (ref $vector_object)
                                (local.get $0))
                              (then
                                (call $vector_ref
                                  (ref.cast
                                    (ref $vector_object)
                                    (local.get $0))
                                  (i32.const 0)))
                              (else
                                (array.get $slots
                                  (ref.cast
                                    (ref $slots)
                                    (local.get $0))
                                  (i32.const 0)))))))
                      (local.get $0))))
                (then
                  (i64.extend_i32_s
                    (i31.get_s
                      (ref.cast
                        (ref i31)
                        (local.get $0)))))
                (else
                  (struct.get $integer 0
                    (ref.cast
                      (ref $integer)
                      (local.get $0))))))
            (br_if $block
              (ref.eq
                (local.get $1)
                (global.get $uninitialized)))
            (block $block3
              (return
                (block $block15
                  (result
                    (ref $vector_object))
                  (local.set $6
                    (if
                      (result i64)
                      (ref.test
                        (ref i31)
                        (local.tee $0
                          (block $block5
                            (result eqref)
                            (if
                              (ref.test
                                (ref $values)
                                (local.tee $0
                                  (if
                                    (result eqref)
                                    (if
                                      (result i32)
                                      (local.tee $2
                                        (i32.ne
                                          (if
                                            (result i32)
                                            (ref.eq
                                              (local.get $1)
                                              (global.get $nil))
                                            (then
                                              (i32.const 1))
                                            (else
                                              (drop
                                                (if
                                                  (result i32)
                                                  (ref.test
                                                    (ref $atom)
                                                    (local.get $1))
                                                  (then
                                                    (i32.lt_s
                                                      (struct.get $atom 0
                                                        (ref.cast
                                                          (ref $atom)
                                                          (local.get $1)))
                                                      (i32.const 0)))
                                                  (else
                                                    (i32.const 0))))
                                              (i32.const 0)))
                                          (i32.const 0)))
                                      (then
                                        (local.get $2))
                                      (else
                                        (br_if $block
                                          (ref.eq
                                            (local.get $1)
                                            (global.get $uninitialized)))
                                        (if
                                          (result i32)
                                          (ref.eq
                                            (local.tee $0
                                              (block $block4
                                                (result eqref)
                                                (if
                                                  (ref.test
                                                    (ref $values)
                                                    (local.tee $0
                                                      (struct.get $pair 1
                                                        (ref.cast
                                                          (ref $pair)
                                                          (local.get $1)))))
                                                  (then
                                                    (br_if $block3
                                                      (i32.ne
                                                        (if
                                                          (result i32)
                                                          (ref.test
                                                            (ref $vector_object)
                                                            (local.tee $0
                                                              (struct.get $values 0
                                                                (ref.cast
                                                                  (ref $values)
                                                                  (local.get $0)))))
                                                          (then
                                                            (struct.get $vector_object 2
                                                              (ref.cast
                                                                (ref $vector_object)
                                                                (local.get $0))))
                                                          (else
                                                            (array.len
                                                              (ref.cast
                                                                (ref $slots)
                                                                (local.get $0)))))
                                                        (i32.const 1)))
                                                    (br $block4
                                                      (if
                                                        (result eqref)
                                                        (ref.test
                                                          (ref $vector_object)
                                                          (local.get $0))
                                                        (then
                                                          (call $vector_ref
                                                            (ref.cast
                                                              (ref $vector_object)
                                                              (local.get $0))
                                                            (i32.const 0)))
                                                        (else
                                                          (array.get $slots
                                                            (ref.cast
                                                              (ref $slots)
                                                              (local.get $0))
                                                            (i32.const 0)))))))
                                                (local.get $0)))
                                            (global.get $nil))
                                          (then
                                            (i32.const 1))
                                          (else
                                            (drop
                                              (if
                                                (result i32)
                                                (ref.test
                                                  (ref $atom)
                                                  (local.get $0))
                                                (then
                                                  (i32.lt_s
                                                    (struct.get $atom 0
                                                      (ref.cast
                                                        (ref $atom)
                                                        (local.get $0)))
                                                    (i32.const 0)))
                                                (else
                                                  (i32.const 0))))
                                            (i32.const 0)))))
                                    (then
                                      (if
                                        (result
                                          (ref eq))
                                        (i64.le_u
                                          (local.tee $6
                                            (i64.extend_i32_u
                                              (struct.get $vector_object 2
                                                (local.get $8))))
                                          (i64.const 1073741823))
                                        (then
                                          (ref.i31
                                            (i32.wrap_i64
                                              (local.get $6))))
                                        (else
                                          (struct.new $integer
                                            (local.get $6)))))
                                    (else
                                      (br_if $block
                                        (ref.eq
                                          (local.get $1)
                                          (global.get $uninitialized)))
                                      (br_if $block
                                        (i32.eqz
                                          (global.get $g211_ready)))
                                      (drop
                                        (struct.get $closure 1
                                          (global.get $g211)))
                                      (call $function3
                                        (local.get $1))))))
                              (then
                                (br_if $block3
                                  (i32.ne
                                    (if
                                      (result i32)
                                      (ref.test
                                        (ref $vector_object)
                                        (local.tee $0
                                          (struct.get $values 0
                                            (ref.cast
                                              (ref $values)
                                              (local.get $0)))))
                                      (then
                                        (struct.get $vector_object 2
                                          (ref.cast
                                            (ref $vector_object)
                                            (local.get $0))))
                                      (else
                                        (array.len
                                          (ref.cast
                                            (ref $slots)
                                            (local.get $0)))))
                                    (i32.const 1)))
                                (br $block5
                                  (if
                                    (result eqref)
                                    (ref.test
                                      (ref $vector_object)
                                      (local.get $0))
                                    (then
                                      (call $vector_ref
                                        (ref.cast
                                          (ref $vector_object)
                                          (local.get $0))
                                        (i32.const 0)))
                                    (else
                                      (array.get $slots
                                        (ref.cast
                                          (ref $slots)
                                          (local.get $0))
                                        (i32.const 0)))))))
                            (local.get $0))))
                      (then
                        (i64.extend_i32_s
                          (i31.get_s
                            (ref.cast
                              (ref i31)
                              (local.get $0)))))
                      (else
                        (struct.get $integer 0
                          (ref.cast
                            (ref $integer)
                            (local.get $0))))))
                  (br_if $block
                    (i32.eqz
                      (global.get $g241_ready)))
                  (local.set $10
                    (if
                      (result
                        (ref eq))
                      (i32.and
                        (i64.le_s
                          (local.get $7)
                          (i64.const 1073741823))
                        (i64.ge_s
                          (local.get $7)
                          (i64.const -1073741824)))
                      (then
                        (ref.i31
                          (i32.wrap_i64
                            (local.get $7))))
                      (else
                        (struct.new $integer
                          (local.get $7)))))
                  (drop
                    (struct.get $closure 1
                      (global.get $g241)))
                  (block $block6
                    (br $block15
                      (block $block14
                        (result
                          (ref $vector_object))
                        (local.set $9
                          (if
                            (result
                              (ref $vector_object))
                            (local.tee $2
                              (i32.wrap_i64
                                (local.tee $6
                                  (if
                                    (result i64)
                                    (ref.test
                                      (ref i31)
                                      (local.tee $0
                                        (block $block7
                                          (result eqref)
                                          (local.set $11
                                            (if
                                              (result
                                                (ref eq))
                                              (i32.and
                                                (i64.le_s
                                                  (local.get $6)
                                                  (i64.const 1073741823))
                                                (i64.ge_s
                                                  (local.get $6)
                                                  (i64.const -1073741824)))
                                              (then
                                                (ref.i31
                                                  (i32.wrap_i64
                                                    (local.get $6))))
                                              (else
                                                (struct.new $integer
                                                  (local.get $6)))))
                                          (if
                                            (ref.test
                                              (ref $values)
                                              (local.tee $0
                                                (call $function61
                                                  (struct.new $environment61
                                                    (if
                                                      (result i64)
                                                      (ref.test
                                                        (ref i31)
                                                        (local.get $10))
                                                      (then
                                                        (i64.extend_i32_s
                                                          (i31.get_s
                                                            (ref.cast
                                                              (ref i31)
                                                              (local.get $10)))))
                                                      (else
                                                        (struct.get $integer 0
                                                          (ref.cast
                                                            (ref $integer)
                                                            (local.get $10)))))
                                                    (if
                                                      (result i64)
                                                      (ref.test
                                                        (ref i31)
                                                        (local.get $11))
                                                      (then
                                                        (i64.extend_i32_s
                                                          (i31.get_s
                                                            (ref.cast
                                                              (ref i31)
                                                              (local.get $11)))))
                                                      (else
                                                        (struct.get $integer 0
                                                          (ref.cast
                                                            (ref $integer)
                                                            (local.get $11))))))
                                                  (if
                                                    (result
                                                      (ref eq))
                                                    (i64.le_u
                                                      (local.tee $6
                                                        (i64.extend_i32_u
                                                          (struct.get $vector_object 2
                                                            (local.get $8))))
                                                      (i64.const 1073741823))
                                                    (then
                                                      (ref.i31
                                                        (i32.wrap_i64
                                                          (local.get $6))))
                                                    (else
                                                      (struct.new $integer
                                                        (local.get $6)))))))
                                            (then
                                              (br_if $block6
                                                (i32.ne
                                                  (if
                                                    (result i32)
                                                    (ref.test
                                                      (ref $vector_object)
                                                      (local.tee $0
                                                        (struct.get $values 0
                                                          (ref.cast
                                                            (ref $values)
                                                            (local.get $0)))))
                                                    (then
                                                      (struct.get $vector_object 2
                                                        (ref.cast
                                                          (ref $vector_object)
                                                          (local.get $0))))
                                                    (else
                                                      (array.len
                                                        (ref.cast
                                                          (ref $slots)
                                                          (local.get $0)))))
                                                  (i32.const 1)))
                                              (br $block7
                                                (if
                                                  (result eqref)
                                                  (ref.test
                                                    (ref $vector_object)
                                                    (local.get $0))
                                                  (then
                                                    (call $vector_ref
                                                      (ref.cast
                                                        (ref $vector_object)
                                                        (local.get $0))
                                                      (i32.const 0)))
                                                  (else
                                                    (array.get $slots
                                                      (ref.cast
                                                        (ref $slots)
                                                        (local.get $0))
                                                      (i32.const 0)))))))
                                          (local.get $0))))
                                    (then
                                      (i64.extend_i32_s
                                        (i31.get_s
                                          (ref.cast
                                            (ref i31)
                                            (local.get $0)))))
                                    (else
                                      (struct.get $integer 0
                                        (ref.cast
                                          (ref $integer)
                                          (local.get $0))))))))
                            (then
                              (struct.new $vector_object
                                (i32.const 5)
                                (array.new $elements:pair
                                  (ref.cast
                                    (ref $pair)
                                    (call $vector_ref
                                      (local.get $8)
                                      (i32.const 0)))
                                  (local.get $2))
                                (local.get $2)))
                            (else
                              (struct.new $vector_object
                                (i32.const 5)
                                (array.new_fixed $elements:pair 0)
                                (i32.const 0)))))
                        (br_if $block
                          (local.tee $2
                            (ref.eq
                              (local.get $1)
                              (global.get $uninitialized))))
                        (block $block8
                          (drop
                            (if
                              (result
                                (ref null $atom))
                              (ref.eq
                                (if
                                  (result
                                    (ref $atom))
                                  (ref.test
                                    (ref $pair)
                                    (local.get $1))
                                  (then
                                    (br_if $block
                                      (local.get $2))
                                    (if
                                      (result
                                        (ref $atom))
                                      (ref.test
                                        (ref $pair)
                                        (block $block9
                                          (result eqref)
                                          (if
                                            (ref.test
                                              (ref $values)
                                              (local.tee $0
                                                (struct.get $pair 1
                                                  (ref.cast
                                                    (ref $pair)
                                                    (local.get $1)))))
                                            (then
                                              (br_if $block8
                                                (i32.ne
                                                  (if
                                                    (result i32)
                                                    (ref.test
                                                      (ref $vector_object)
                                                      (local.tee $0
                                                        (struct.get $values 0
                                                          (ref.cast
                                                            (ref $values)
                                                            (local.get $0)))))
                                                    (then
                                                      (struct.get $vector_object 2
                                                        (ref.cast
                                                          (ref $vector_object)
                                                          (local.get $0))))
                                                    (else
                                                      (array.len
                                                        (ref.cast
                                                          (ref $slots)
                                                          (local.get $0)))))
                                                  (i32.const 1)))
                                              (br $block9
                                                (if
                                                  (result eqref)
                                                  (ref.test
                                                    (ref $vector_object)
                                                    (local.get $0))
                                                  (then
                                                    (call $vector_ref
                                                      (ref.cast
                                                        (ref $vector_object)
                                                        (local.get $0))
                                                      (i32.const 0)))
                                                  (else
                                                    (array.get $slots
                                                      (ref.cast
                                                        (ref $slots)
                                                        (local.get $0))
                                                      (i32.const 0)))))))
                                          (local.get $0)))
                                      (then
                                        (br_if $block
                                          (ref.eq
                                            (local.get $1)
                                            (global.get $uninitialized)))
                                        (br_if $block
                                          (i32.eqz
                                            (global.get $g213_ready)))
                                        (drop
                                          (struct.get $closure 1
                                            (global.get $g213)))
                                        (select
                                          (result
                                            (ref $atom))
                                          (global.get $true)
                                          (global.get $false)
                                          (ref.test
                                            (ref $pair)
                                            (block $block10
                                              (result eqref)
                                              (if
                                                (ref.test
                                                  (ref $values)
                                                  (local.tee $0
                                                    (call $function5
                                                      (local.get $1))))
                                                (then
                                                  (br_if $block8
                                                    (i32.ne
                                                      (if
                                                        (result i32)
                                                        (ref.test
                                                          (ref $vector_object)
                                                          (local.tee $0
                                                            (struct.get $values 0
                                                              (ref.cast
                                                                (ref $values)
                                                                (local.get $0)))))
                                                        (then
                                                          (struct.get $vector_object 2
                                                            (ref.cast
                                                              (ref $vector_object)
                                                              (local.get $0))))
                                                        (else
                                                          (array.len
                                                            (ref.cast
                                                              (ref $slots)
                                                              (local.get $0)))))
                                                      (i32.const 1)))
                                                  (br $block10
                                                    (if
                                                      (result eqref)
                                                      (ref.test
                                                        (ref $vector_object)
                                                        (local.get $0))
                                                      (then
                                                        (call $vector_ref
                                                          (ref.cast
                                                            (ref $vector_object)
                                                            (local.get $0))
                                                          (i32.const 0)))
                                                      (else
                                                        (array.get $slots
                                                          (ref.cast
                                                            (ref $slots)
                                                            (local.get $0))
                                                          (i32.const 0)))))))
                                              (local.get $0)))))
                                      (else
                                        (global.get $false))))
                                  (else
                                    (global.get $false)))
                                (global.get $false))
                              (then
                                (global.get $unspecified))
                              (else
                                (br_if $block
                                  (i32.eqz
                                    (global.get $g122_ready)))
                                (drop
                                  (struct.get $closure 1
                                    (global.get $g122)))
                                (drop
                                  (call $abi_take
                                    (call $snail:error
                                      (local.tee $2
                                        (call $abi_root
                                          (array.new_fixed $slots 1
                                            (global.get $literal3)))))))
                                (if
                                  (i32.ge_u
                                    (local.get $2)
                                    (global.get $abi_used))
                                  (then
                                    (unreachable)))
                                (if
                                  (i32.ne
                                    (array.get $text
                                      (global.get $abi_links)
                                      (local.get $2))
                                    (i32.const -1))
                                  (then
                                    (unreachable)))
                                (drop
                                  (table.get $abi_roots
                                    (local.get $2)))
                                (table.set $abi_roots
                                  (local.get $2)
                                  (ref.null none))
                                (array.set $text
                                  (global.get $abi_links)
                                  (local.get $2)
                                  (global.get $abi_free))
                                (global.set $abi_free
                                  (local.get $2))
                                (global.set $abi_live
                                  (i32.sub
                                    (global.get $abi_live)
                                    (i32.const 1)))
                                (ref.null none))))
                          (if
                            (i32.gt_u
                              (local.tee $2
                                (i32.wrap_i64
                                  (local.get $6)))
                              (struct.get $vector_object 2
                                (local.get $9)))
                            (then
                              (unreachable)))
                          (if
                            (i32.or
                              (i32.lt_u
                                (local.tee $3
                                  (struct.get $vector_object 2
                                    (local.get $8)))
                                (local.tee $4
                                  (i32.wrap_i64
                                    (local.get $7))))
                              (i32.gt_u
                                (local.get $2)
                                (i32.sub
                                  (local.get $3)
                                  (local.get $4))))
                            (then
                              (unreachable)))
                          (block $block11
                            (br_if $block11
                              (i32.eqz
                                (local.get $2)))
                            (if
                              (i32.eq
                                (local.tee $3
                                  (struct.get $vector_object 0
                                    (local.get $9)))
                                (struct.get $vector_object 0
                                  (local.get $8)))
                              (then
                                (if
                                  (i32.eqz
                                    (local.get $3))
                                  (then
                                    (array.copy $slots $slots
                                      (ref.cast
                                        (ref $slots)
                                        (struct.get $vector_object 1
                                          (local.get $9)))
                                      (i32.const 0)
                                      (ref.cast
                                        (ref $slots)
                                        (struct.get $vector_object 1
                                          (local.get $8)))
                                      (local.get $4)
                                      (local.get $2))
                                    (br $block11)))
                                (if
                                  (i32.eq
                                    (local.get $3)
                                    (i32.const 1))
                                  (then
                                    (array.copy $elements:integer $elements:integer
                                      (ref.cast
                                        (ref $elements:integer)
                                        (struct.get $vector_object 1
                                          (local.get $9)))
                                      (i32.const 0)
                                      (ref.cast
                                        (ref $elements:integer)
                                        (struct.get $vector_object 1
                                          (local.get $8)))
                                      (local.get $4)
                                      (local.get $2))
                                    (br $block11)))
                                (if
                                  (i32.eq
                                    (local.get $3)
                                    (i32.const 2))
                                  (then
                                    (array.copy $elements:real $elements:real
                                      (ref.cast
                                        (ref $elements:real)
                                        (struct.get $vector_object 1
                                          (local.get $9)))
                                      (i32.const 0)
                                      (ref.cast
                                        (ref $elements:real)
                                        (struct.get $vector_object 1
                                          (local.get $8)))
                                      (local.get $4)
                                      (local.get $2))
                                    (br $block11)))
                                (block $block12
                                  (br_if $block12
                                    (i32.eq
                                      (local.get $3)
                                      (i32.const 3)))
                                  (br_if $block12
                                    (i32.eq
                                      (local.get $3)
                                      (i32.const 4)))
                                  (if
                                    (i32.eq
                                      (local.get $3)
                                      (i32.const 5))
                                    (then
                                      (array.copy $elements:pair $elements:pair
                                        (ref.cast
                                          (ref $elements:pair)
                                          (struct.get $vector_object 1
                                            (local.get $9)))
                                        (i32.const 0)
                                        (ref.cast
                                          (ref $elements:pair)
                                          (struct.get $vector_object 1
                                            (local.get $8)))
                                        (local.get $4)
                                        (local.get $2))
                                      (br $block11)))
                                  (if
                                    (i32.eq
                                      (local.get $3)
                                      (i32.const 6))
                                    (then
                                      (array.copy $elements:vector $elements:vector
                                        (ref.cast
                                          (ref $elements:vector)
                                          (struct.get $vector_object 1
                                            (local.get $9)))
                                        (i32.const 0)
                                        (ref.cast
                                          (ref $elements:vector)
                                          (struct.get $vector_object 1
                                            (local.get $8)))
                                        (local.get $4)
                                        (local.get $2))
                                      (br $block11)))
                                  (if
                                    (i32.eq
                                      (local.get $3)
                                      (i32.const 7))
                                    (then
                                      (array.copy $elements:string $elements:string
                                        (ref.cast
                                          (ref $elements:string)
                                          (struct.get $vector_object 1
                                            (local.get $9)))
                                        (i32.const 0)
                                        (ref.cast
                                          (ref $elements:string)
                                          (struct.get $vector_object 1
                                            (local.get $8)))
                                        (local.get $4)
                                        (local.get $2))
                                      (br $block11)))
                                  (if
                                    (i32.eq
                                      (local.get $3)
                                      (i32.const 8))
                                    (then
                                      (array.copy $elements:bytevector $elements:bytevector
                                        (ref.cast
                                          (ref $elements:bytevector)
                                          (struct.get $vector_object 1
                                            (local.get $9)))
                                        (i32.const 0)
                                        (ref.cast
                                          (ref $elements:bytevector)
                                          (struct.get $vector_object 1
                                            (local.get $8)))
                                        (local.get $4)
                                        (local.get $2))
                                      (br $block11)))
                                  (if
                                    (i32.eq
                                      (local.get $3)
                                      (i32.const 9))
                                    (then
                                      (array.copy $elements:closure $elements:closure
                                        (ref.cast
                                          (ref $elements:closure)
                                          (struct.get $vector_object 1
                                            (local.get $9)))
                                        (i32.const 0)
                                        (ref.cast
                                          (ref $elements:closure)
                                          (struct.get $vector_object 1
                                            (local.get $8)))
                                        (local.get $4)
                                        (local.get $2))
                                      (br $block11)))
                                  (if
                                    (i32.eq
                                      (local.get $3)
                                      (i32.const 10))
                                    (then
                                      (array.copy $elements:record $elements:record
                                        (ref.cast
                                          (ref $elements:record)
                                          (struct.get $vector_object 1
                                            (local.get $9)))
                                        (i32.const 0)
                                        (ref.cast
                                          (ref $elements:record)
                                          (struct.get $vector_object 1
                                            (local.get $8)))
                                        (local.get $4)
                                        (local.get $2))
                                      (br $block11)))
                                  (if
                                    (i32.eq
                                      (local.get $3)
                                      (i32.const 11))
                                    (then
                                      (array.copy $elements:complex $elements:complex
                                        (ref.cast
                                          (ref $elements:complex)
                                          (struct.get $vector_object 1
                                            (local.get $9)))
                                        (i32.const 0)
                                        (ref.cast
                                          (ref $elements:complex)
                                          (struct.get $vector_object 1
                                            (local.get $8)))
                                        (local.get $4)
                                        (local.get $2))
                                      (br $block11)))
                                  (br_if $block12
                                    (i32.eq
                                      (local.get $3)
                                      (i32.const 12)))
                                  (if
                                    (i32.eq
                                      (local.get $3)
                                      (i32.const 13))
                                    (then
                                      (array.copy $elements:f32 $elements:f32
                                        (ref.cast
                                          (ref $elements:f32)
                                          (struct.get $vector_object 1
                                            (local.get $9)))
                                        (i32.const 0)
                                        (ref.cast
                                          (ref $elements:f32)
                                          (struct.get $vector_object 1
                                            (local.get $8)))
                                        (local.get $4)
                                        (local.get $2))))
                                  (br $block11))
                                (array.copy $text $text
                                  (ref.cast
                                    (ref $text)
                                    (struct.get $vector_object 1
                                      (local.get $9)))
                                  (i32.const 0)
                                  (ref.cast
                                    (ref $text)
                                    (struct.get $vector_object 1
                                      (local.get $8)))
                                  (local.get $4)
                                  (local.get $2))
                                (br $block11)))
                            (loop $label
                              (if
                                (i32.gt_u
                                  (local.get $2)
                                  (local.get $5))
                                (then
                                  (local.set $0
                                    (call $vector_ref
                                      (local.get $8)
                                      (i32.add
                                        (local.get $4)
                                        (local.get $5))))
                                  (if
                                    (i32.or
                                      (i32.gt_u
                                        (local.get $5)
                                        (local.tee $3
                                          (struct.get $vector_object 2
                                            (local.get $9))))
                                      (i32.eq
                                        (local.get $3)
                                        (local.get $5)))
                                    (then
                                      (unreachable)))
                                  (if
                                    (i32.eqz
                                      (call $storage_accepts
                                        (struct.get $vector_object 0
                                          (local.get $9))
                                        (local.get $0)))
                                    (then
                                      (global.set $error_code
                                        (i32.const 1))
                                      (local.set $4
                                        (i32.load
                                          (i32.const 1062292)))
                                      (br $block13
                                        (i32.load
                                          (i32.const 1062332)))))
                                  (call $vector_store
                                    (local.get $9)
                                    (local.get $5)
                                    (local.get $0))
                                  (local.set $5
                                    (i32.add
                                      (local.get $5)
                                      (i32.const 1)))
                                  (br $label)))))
                          (br $block14
                            (local.get $9)))
                        (br $block6))))
                  (br $block16)))))
          (br $block16))
        (global.set $error_code
          (i32.const 6))
        (local.set $4
          (i32.load
            (i32.const 1062312)))
        (br $block13
          (i32.load
            (i32.const 1062352))))
      (global.set $error_code
        (i32.const 5))
      (local.set $4
        (i32.load
          (i32.const 1062308)))
      (i32.load
        (i32.const 1062348))))
  (global.set $__stack_pointer
    (local.tee $2
      (i32.sub
        (global.get $__stack_pointer)
        (i32.const 32))))
  (call $_RNvMNtCsi9YzqDQQz2q_5alloc6stringNtB2_6String15from_utf8_lossy
    (local.tee $5
      (i32.add
        (local.get $2)
        (i32.const 12)))
    (local.get $3)
    (local.get $4))
  (i64.store offset=24
    (local.get $2)
    (i64.or
      (i64.extend_i32_u
        (local.get $5))
      (i64.const 103079215104)))
  (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio7__eprint
    (i32.add
      (local.get $2)
      (i32.const 24)))
  (local.set $4
    (i32.load offset=16
      (local.get $2)))
  (if
    (i32.gt_s
      (i32.load offset=12
        (local.get $2))
      (i32.const 0))
    (then
      (call $dlfree
        (local.get $4))))
  (call $_RNvNtCset5xJoy1xWQ_3std2rt7cleanup)
  (call $__imported_wasi_snapshot_preview1_proc_exit
    (i32.const 1))
  (unreachable))

(func $function165
  (type $35)
  (param $0 eqref)
  (param $1 eqref)
  (param $2 nullref)
  (result eqref)
  (local $3 i32)
  (local $4 i32)
  (local $5 i32)
  (local $6 i32)
  (local $7 i64)
  (local $8 i64)
  (local $9
    (ref $vector_object))
  (local $10
    (ref eq))
  (local $11
    (ref i31))
  (local $12
    (ref $slots))
  (local $13
    (ref null $pair))
  (local $14
    (ref $binding_cell0))
  (local.set $5
    (block $block1
      (result i32)
      (block $block
        (return
          (if
            (result
              (ref $atom))
            (if
              (result i32)
              (i32.and
                (ref.test
                  (ref i31)
                  (local.tee $10
                    (if
                      (result
                        (ref eq))
                      (i32.and
                        (i64.le_s
                          (local.tee $7
                            (if
                              (result i64)
                              (ref.test
                                (ref i31)
                                (local.get $1))
                              (then
                                (i64.extend_i32_s
                                  (i31.get_s
                                    (ref.cast
                                      (ref i31)
                                      (local.get $1)))))
                              (else
                                (struct.get $integer 0
                                  (ref.cast
                                    (ref $integer)
                                    (local.get $1))))))
                          (i64.const 1073741823))
                        (i64.ge_s
                          (local.get $7)
                          (i64.const -1073741824)))
                      (then
                        (ref.i31
                          (i32.wrap_i64
                            (local.get $7))))
                      (else
                        (struct.new $integer
                          (local.get $7))))))
                (block
                  (result i32)
                  (br_if $block
                    (i32.or
                      (ref.is_null
                        (local.tee $1
                          (global.get $g284)))
                      (ref.eq
                        (local.get $1)
                        (global.get $uninitialized))))
                  (ref.test
                    (ref i31)
                    (local.get $1))))
              (then
                (i32.lt_s
                  (i31.get_s
                    (ref.cast
                      (ref i31)
                      (local.get $10)))
                  (i31.get_s
                    (ref.cast
                      (ref i31)
                      (local.get $1)))))
              (else
                (i32.and
                  (i32.ne
                    (local.tee $3
                      (call $cold.compare
                        (local.get $10)
                        (local.get $1)))
                    (i32.const 2))
                  (i32.lt_s
                    (local.get $3)
                    (i32.const 0)))))
            (then
              (br_if $block
                (i32.eqz
                  (global.get $g286_ready)))
              (local.set $9
                (ref.as_non_null
                  (global.get $g286)))
              (if
                (i64.gt_u
                  (local.get $7)
                  (i64.const 2147483647))
                (then
                  (global.set $error_code
                    (i32.const 3))
                  (local.set $3
                    (i32.load
                      (i32.const 1062300)))
                  (br $block1
                    (i32.load
                      (i32.const 1062340)))))
              (local.set $3
                (i32.wrap_i64
                  (local.get $7)))
              (local.set $11
                (ref.i31
                  (i32.const 1)))
              (local.set $1
                (if
                  (result eqref)
                  (ref.test
                    (ref i31)
                    (local.tee $1
                      (block $block2
                        (result eqref)
                        (if
                          (ref.test
                            (ref $values)
                            (local.tee $1
                              (struct.get $pair 0
                                (local.tee $13
                                  (if
                                    (result
                                      (ref $pair))
                                    (i32.eq
                                      (struct.get $vector_object 0
                                        (local.get $9))
                                      (i32.const 5))
                                    (then
                                      (array.get $elements:pair
                                        (ref.cast
                                          (ref $elements:pair)
                                          (struct.get $vector_object 1
                                            (local.get $9)))
                                        (local.get $3)))
                                    (else
                                      (ref.cast
                                        (ref $pair)
                                        (call $vector_ref
                                          (local.get $9)
                                          (local.get $3)))))))))
                          (then
                            (if
                              (i32.ne
                                (if
                                  (result i32)
                                  (ref.test
                                    (ref $vector_object)
                                    (local.tee $1
                                      (struct.get $values 0
                                        (ref.cast
                                          (ref $values)
                                          (local.get $1)))))
                                  (then
                                    (struct.get $vector_object 2
                                      (ref.cast
                                        (ref $vector_object)
                                        (local.get $1))))
                                  (else
                                    (array.len
                                      (ref.cast
                                        (ref $slots)
                                        (local.get $1)))))
                                (i32.const 1))
                              (then
                                (global.set $error_code
                                  (i32.const 5))
                                (local.set $3
                                  (i32.load
                                    (i32.const 1062308)))
                                (br $block1
                                  (i32.load
                                    (i32.const 1062348)))))
                            (br $block2
                              (if
                                (result eqref)
                                (ref.test
                                  (ref $vector_object)
                                  (local.get $1))
                                (then
                                  (call $vector_ref
                                    (ref.cast
                                      (ref $vector_object)
                                      (local.get $1))
                                    (i32.const 0)))
                                (else
                                  (array.get $slots
                                    (ref.cast
                                      (ref $slots)
                                      (local.get $1))
                                    (i32.const 0)))))))
                        (local.get $1))))
                  (then
                    (if
                      (result eqref)
                      (i32.le_u
                        (i32.add
                          (local.tee $3
                            (i32.add
                              (i31.get_s
                                (ref.cast
                                  (ref i31)
                                  (local.get $1)))
                              (i32.const 1)))
                          (i32.const 1073741824))
                        (i32.const 2147483647))
                      (then
                        (ref.i31
                          (local.get $3)))
                      (else
                        (call $cold.checked_add
                          (local.get $1)
                          (local.get $11)))))
                  (else
                    (call $cold.checked_add
                      (local.get $1)
                      (local.get $11)))))
              (br_if $block
                (i32.eqz
                  (global.get $g60_ready)))
              (drop
                (struct.get $closure 1
                  (global.get $g60)))
              (if
                (i32.or
                  (i32.ne
                    (local.tee $3
                      (array.len
                        (local.tee $12
                          (array.new_fixed $slots 2
                            (ref.as_non_null
                              (local.get $13))
                            (local.get $1)))))
                    (i32.const 2))
                  (i32.lt_u
                    (local.get $3)
                    (i32.const 2)))
                (then
                  (global.set $error_code
                    (i32.const 4))
                  (local.set $3
                    (i32.load
                      (i32.const 1062304)))
                  (br $block1
                    (i32.load
                      (i32.const 1062344)))))
              (struct.set $pair 0
                (ref.cast
                  (ref $pair)
                  (array.get $slots
                    (local.get $12)
                    (i32.const 0)))
                (array.get $slots
                  (local.get $12)
                  (i32.const 1)))
              (if
                (i64.lt_s
                  (i64.and
                    (i64.xor
                      (local.get $7)
                      (local.tee $8
                        (i64.add
                          (local.get $7)
                          (i64.const 1))))
                    (i64.xor
                      (local.get $8)
                      (i64.const 1)))
                  (i64.const 0))
                (then
                  (global.set $error_code
                    (i32.const 2))
                  (local.set $3
                    (i32.load
                      (i32.const 1062296)))
                  (br $block1
                    (i32.load
                      (i32.const 1062336)))))
              (br_if $block
                (i32.eqz
                  (struct.get $binding_cell0 0
                    (local.tee $14
                      (struct.get $environment162 0
                        (ref.cast
                          (ref $environment162)
                          (local.get $0)))))))
              (return_call $function165
                (struct.get $closure 1
                  (struct.get $binding_cell0 1
                    (local.get $14)))
                (if
                  (result
                    (ref eq))
                  (i32.and
                    (i64.le_s
                      (local.get $8)
                      (i64.const 1073741823))
                    (i64.ge_s
                      (local.get $8)
                      (i64.const -1073741824)))
                  (then
                    (ref.i31
                      (i32.wrap_i64
                        (local.get $8))))
                  (else
                    (struct.new $integer
                      (local.get $8))))
                (local.get $2)))
            (else
              (global.get $unspecified)))))
      (global.set $error_code
        (i32.const 6))
      (local.set $3
        (i32.load
          (i32.const 1062312)))
      (i32.load
        (i32.const 1062352))))
  (global.set $__stack_pointer
    (local.tee $4
      (i32.sub
        (global.get $__stack_pointer)
        (i32.const 32))))
  (call $_RNvMNtCsi9YzqDQQz2q_5alloc6stringNtB2_6String15from_utf8_lossy
    (local.tee $6
      (i32.add
        (local.get $4)
        (i32.const 12)))
    (local.get $5)
    (local.get $3))
  (i64.store offset=24
    (local.get $4)
    (i64.or
      (i64.extend_i32_u
        (local.get $6))
      (i64.const 103079215104)))
  (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio7__eprint
    (i32.add
      (local.get $4)
      (i32.const 24)))
  (local.set $3
    (i32.load offset=16
      (local.get $4)))
  (if
    (i32.gt_s
      (i32.load offset=12
        (local.get $4))
      (i32.const 0))
    (then
      (call $dlfree
        (local.get $3))))
  (call $_RNvNtCset5xJoy1xWQ_3std2rt7cleanup)
  (call $__imported_wasi_snapshot_preview1_proc_exit
    (i32.const 1))
  (unreachable))
