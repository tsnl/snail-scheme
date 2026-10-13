;; Extracted from final optimized Wasm; dependencies outside this projection are retained in the raw archive.
(type $binding_cell0
  (struct
    (field
      (mut f64))))

(type $environment163
  (struct
    (field
      (ref $binding_cell0))))

(type $float
  (struct
    (field f64)))

(func $adapter163
  (type $call)
  (param $0 eqref)
  (param $1
    (ref $slots))
  (param $2 nullref)
  (result eqref)
  (local $3 i32)
  (local $4 i32)
  (local $5 i32)
  (local $6 i32)
  (local $7
    (ref $environment163))
  (if
    (array.len
      (local.get $1))
    (then
      (global.set $error_code
        (i32.const 4))
      (local.set $4
        (i32.load
          (i32.const 1062344)))
      (local.set $5
        (i32.load
          (i32.const 1062304)))
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
        (local.get $4)
        (local.get $5))
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
      (unreachable)))
  (struct.set $binding_cell0 0
    (struct.get $environment163 0
      (local.tee $7
        (ref.cast
          (ref $environment163)
          (local.get $0))))
    (f64.add
      (struct.get $binding_cell0 0
        (struct.get $environment163 0
          (local.get $7)))
      (f64.const 0.5)))
  (global.get $unspecified))

(func $adapter164
  (type $call)
  (param $0 eqref)
  (param $1
    (ref $slots))
  (param $2 nullref)
  (result eqref)
  (local $3 i32)
  (local $4 i32)
  (local $5 i32)
  (local $6 i32)
  (if
    (array.len
      (local.get $1))
    (then
      (global.set $error_code
        (i32.const 4))
      (local.set $4
        (i32.load
          (i32.const 1062344)))
      (local.set $5
        (i32.load
          (i32.const 1062304)))
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
        (local.get $4)
        (local.get $5))
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
      (unreachable)))
  (struct.new $float
    (struct.get $binding_cell0 0
      (struct.get $environment163 0
        (ref.cast
          (ref $environment163)
          (local.get $0))))))
