;; Extracted from final optimized Wasm; dependencies outside this projection are retained in the raw archive.
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

(type $elements:integer
  (array
    (mut i64)))

(type $environment162
  (struct
    (field
      (ref $binding_cell0))))

(type $integer
  (struct
    (field i64)))

(type $vector_object
  (struct
    (field i32)
    (field
      (ref array))
    (field i32)))

(func $vector_set:integer
  (type $54)
  (param $0
    (ref $vector_object))
  (param $1 i32)
  (param $2 i64)
  (local $3 i32)
  (local $4 i32)
  (local $5 i32)
  (local $6
    (ref eq))
  (if
    (i32.eq
      (struct.get $vector_object 0
        (local.get $0))
      (i32.const 1))
    (then
      (array.set $elements:integer
        (ref.cast
          (ref $elements:integer)
          (struct.get $vector_object 1
            (local.get $0)))
        (local.get $1)
        (local.get $2)))
    (else
      (if
        (i32.or
          (i32.gt_u
            (local.get $1)
            (local.tee $3
              (struct.get $vector_object 2
                (local.get $0))))
          (i32.eq
            (local.get $1)
            (local.get $3)))
        (then
          (unreachable)))
      (if
        (i32.eqz
          (call $storage_accepts
            (struct.get $vector_object 0
              (local.get $0))
            (local.tee $6
              (if
                (result
                  (ref eq))
                (i32.and
                  (i64.le_s
                    (local.get $2)
                    (i64.const 1073741823))
                  (i64.ge_s
                    (local.get $2)
                    (i64.const -1073741824)))
                (then
                  (ref.i31
                    (i32.wrap_i64
                      (local.get $2))))
                (else
                  (struct.new $integer
                    (local.get $2)))))))
        (then
          (global.set $error_code
            (i32.const 1))
          (local.set $3
            (i32.load
              (i32.const 1062332)))
          (local.set $4
            (i32.load
              (i32.const 1062292)))
          (global.set $__stack_pointer
            (local.tee $1
              (i32.sub
                (global.get $__stack_pointer)
                (i32.const 32))))
          (call $_RNvMNtCsi9YzqDQQz2q_5alloc6stringNtB2_6String15from_utf8_lossy
            (local.tee $5
              (i32.add
                (local.get $1)
                (i32.const 12)))
            (local.get $3)
            (local.get $4))
          (i64.store offset=24
            (local.get $1)
            (i64.or
              (i64.extend_i32_u
                (local.get $5))
              (i64.const 103079215104)))
          (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio7__eprint
            (i32.add
              (local.get $1)
              (i32.const 24)))
          (local.set $3
            (i32.load offset=16
              (local.get $1)))
          (if
            (i32.gt_s
              (i32.load offset=12
                (local.get $1))
              (i32.const 0))
            (then
              (call $dlfree
                (local.get $3))))
          (call $_RNvNtCset5xJoy1xWQ_3std2rt7cleanup)
          (call $__imported_wasi_snapshot_preview1_proc_exit
            (i32.const 1))
          (unreachable)))
      (call $vector_store
        (local.get $0)
        (local.get $1)
        (local.get $6)))))

(func $function165
  (type $32)
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
  (local $9 i64)
  (local $10
    (ref $vector_object))
  (local $11
    (ref eq))
  (local $12
    (ref $binding_cell0))
  (local.set $5
    (block $block3
      (result i32)
      (block $block1
        (block $block
          (block $block2
            (return
              (if
                (result
                  (ref $atom))
                (if
                  (result i32)
                  (i32.and
                    (ref.test
                      (ref i31)
                      (local.tee $11
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
                          (local.get $11)))
                      (i31.get_s
                        (ref.cast
                          (ref i31)
                          (local.get $1)))))
                  (else
                    (i32.and
                      (i32.ne
                        (local.tee $3
                          (call $cold.compare
                            (local.get $11)
                            (local.get $1)))
                        (i32.const 2))
                      (i32.lt_s
                        (local.get $3)
                        (i32.const 0)))))
                (then
                  (br_if $block
                    (local.tee $3
                      (i32.eqz
                        (global.get $g286_ready))))
                  (local.set $10
                    (ref.as_non_null
                      (global.get $g286)))
                  (br_if $block
                    (local.get $3))
                  (br_if $block1
                    (i64.gt_u
                      (local.get $7)
                      (i64.const 2147483647)))
                  (local.set $3
                    (i32.wrap_i64
                      (local.get $7)))
                  (br_if $block2
                    (i64.lt_s
                      (i64.and
                        (i64.xor
                          (local.tee $8
                            (i64.add
                              (local.tee $9
                                (if
                                  (result i64)
                                  (i32.eq
                                    (struct.get $vector_object 0
                                      (local.get $10))
                                    (i32.const 1))
                                  (then
                                    (array.get $elements:integer
                                      (ref.cast
                                        (ref $elements:integer)
                                        (struct.get $vector_object 1
                                          (local.get $10)))
                                      (local.get $3)))
                                  (else
                                    (if
                                      (result i64)
                                      (ref.test
                                        (ref i31)
                                        (local.tee $1
                                          (call $vector_ref
                                            (local.get $10)
                                            (local.get $3))))
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
                                            (local.get $1))))))))
                              (i64.const 1)))
                          (local.get $9))
                        (i64.xor
                          (local.get $8)
                          (i64.const 1)))
                      (i64.const 0)))
                  (br_if $block1
                    (i64.gt_u
                      (local.get $7)
                      (i64.const 2147483647)))
                  (call $vector_set:integer
                    (local.get $10)
                    (i32.wrap_i64
                      (local.get $7))
                    (local.get $8))
                  (br_if $block2
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
                      (i64.const 0)))
                  (br_if $block
                    (i32.eqz
                      (struct.get $binding_cell0 0
                        (local.tee $12
                          (struct.get $environment162 0
                            (ref.cast
                              (ref $environment162)
                              (local.get $0)))))))
                  (return_call $function165
                    (struct.get $closure 1
                      (struct.get $binding_cell0 1
                        (local.get $12)))
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
            (i32.const 2))
          (local.set $4
            (i32.load
              (i32.const 1062296)))
          (br $block3
            (i32.load
              (i32.const 1062336))))
        (global.set $error_code
          (i32.const 6))
        (local.set $4
          (i32.load
            (i32.const 1062312)))
        (br $block3
          (i32.load
            (i32.const 1062352))))
      (global.set $error_code
        (i32.const 3))
      (local.set $4
        (i32.load
          (i32.const 1062300)))
      (i32.load
        (i32.const 1062340))))
  (global.set $__stack_pointer
    (local.tee $3
      (i32.sub
        (global.get $__stack_pointer)
        (i32.const 32))))
  (call $_RNvMNtCsi9YzqDQQz2q_5alloc6stringNtB2_6String15from_utf8_lossy
    (local.tee $6
      (i32.add
        (local.get $3)
        (i32.const 12)))
    (local.get $5)
    (local.get $4))
  (i64.store offset=24
    (local.get $3)
    (i64.or
      (i64.extend_i32_u
        (local.get $6))
      (i64.const 103079215104)))
  (call $_RNvNtNtCset5xJoy1xWQ_3std2io5stdio7__eprint
    (i32.add
      (local.get $3)
      (i32.const 24)))
  (local.set $4
    (i32.load offset=16
      (local.get $3)))
  (if
    (i32.gt_s
      (i32.load offset=12
        (local.get $3))
      (i32.const 0))
    (then
      (call $dlfree
        (local.get $4))))
  (call $_RNvNtCset5xJoy1xWQ_3std2rt7cleanup)
  (call $__imported_wasi_snapshot_preview1_proc_exit
    (i32.const 1))
  (unreachable))
