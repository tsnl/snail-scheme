;; Exact original optimized function $function132, import-inclusive index 142.
;; Full module and referenced definitions are retained in raw-artifacts.tar.xz.
(func $function132
  (type $27)
  (param $0 (ref $vector))
  (param $1 eqref)
  (param $2 nullref)
  (result eqref)
  (local $3 i32)
  (local $4 i32)
  (local $5 i32)
  (local $6 i32)
  (local $7 eqref)
  (local $8 (ref $vector))
  (local $9 (ref $vector))
  (local $10 (ref null $closure))
  (local.set $5
    (block $block1
      (result i32)
      (block $block2
        (block $block
          (br_if $block
            (i32.or (ref.is_null (local.get $1)) (ref.eq (local.get $1) (global.get $uninitialized)))
          )
          (br_if $block (ref.is_null (local.tee $10 (global.get $g146))))
          (drop (ref.as_non_null (local.get $10)))
          (if
            (i32.or
              (i32.ne
                (local.tee $3 (array.len (local.tee $9 (array.new_fixed $vector 1 (local.get $1)))))
                (i32.const 1)
              )
              (i32.eqz (local.get $3))
            )
            (then
              (global.set $error_code (i32.const 4))
              (local.set $4 (i32.load (i32.const 1062304)))
              (br $block1 (i32.load (i32.const 1062344)))
            )
          )
          (return
            (if
              (result (ref $atom))
              (ref.eq (array.get $vector (local.get $9) (i32.const 0)) (global.get $eof))
              (then (global.get $unspecified))
              (else
                (br_if $block
                  (i32.or (ref.is_null (local.get $1)) (ref.eq (local.get $1) (global.get $uninitialized)))
                )
                (local.set $7
                  (block $block3
                    (result eqref)
                    (br_if $block
                      (i32.or
                        (ref.is_null (local.tee $7 (array.get $vector (local.get $0) (i32.const 0))))
                        (ref.eq (local.get $7) (global.get $uninitialized))
                      )
                    )
                    (if
                      (ref.test (ref $values) (local.get $7))
                      (then
                        (br_if $block2
                          (i32.ne
                            (array.len
                              (local.tee $8 (struct.get $values 0 (ref.cast (ref $values) (local.get $7))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block3 (array.get $vector (local.get $8) (i32.const 0)))
                      )
                    )
                    (local.get $7)
                  )
                )
                (br_if $block (ref.is_null (local.tee $10 (global.get $g153))))
                (drop (struct.get $closure 1 (local.get $10)))
                (drop
                  (call $abi_take
                    (call $snail:write-char
                      (local.tee $3
                        (call $abi_root (array.new_fixed $vector 2 (local.get $1) (local.get $7)))
                      )
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
                (local.set $1
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
                              (local.tee $8 (struct.get $values 0 (ref.cast (ref $values) (local.get $1))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block4 (array.get $vector (local.get $8) (i32.const 0)))
                      )
                    )
                    (local.get $1)
                  )
                )
                (return_call $function132
                  (array.new_fixed $vector 2
                    (block $block5
                      (result eqref)
                      (br_if $block
                        (i32.or
                          (ref.is_null (local.tee $7 (array.get $vector (local.get $0) (i32.const 0))))
                          (ref.eq (local.get $7) (global.get $uninitialized))
                        )
                      )
                      (if
                        (ref.test (ref $values) (local.get $7))
                        (then
                          (br_if $block2
                            (i32.ne
                              (array.len
                                (local.tee $8 (struct.get $values 0 (ref.cast (ref $values) (local.get $7))))
                              )
                              (i32.const 1)
                            )
                          )
                          (br $block5 (array.get $vector (local.get $8) (i32.const 0)))
                        )
                      )
                      (local.get $7)
                    )
                    (block
                      (result eqref)
                      (br_if $block (ref.is_null (local.tee $10 (global.get $g251))))
                      (drop (ref.as_non_null (local.get $10)))
                      (local.set $7
                        (block $block6
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
                              (br_if $block2
                                (i32.ne
                                  (array.len
                                    (local.tee $8
                                      (struct.get $values 0 (ref.cast (ref $values) (local.get $1)))
                                    )
                                  )
                                  (i32.const 1)
                                )
                              )
                              (br $block6 (array.get $vector (local.get $8) (i32.const 0)))
                            )
                          )
                          (local.get $1)
                        )
                      )
                      (local.get $1)
                    )
                  )
                  (block $block7
                    (result eqref)
                    (br_if $block (ref.is_null (local.tee $10 (global.get $g137))))
                    (drop (struct.get $closure 1 (local.get $10)))
                    (local.set $1
                      (call $abi_take
                        (call $snail:read-char
                          (local.tee $3 (call $abi_root (array.new_fixed $vector 1 (local.get $7))))
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
                        (br_if $block2
                          (i32.ne
                            (array.len
                              (local.tee $8 (struct.get $values 0 (ref.cast (ref $values) (local.get $1))))
                            )
                            (i32.const 1)
                          )
                        )
                        (br $block7 (array.get $vector (local.get $8) (i32.const 0)))
                      )
                    )
                    (local.get $1)
                  )
                  (local.get $2)
                )
              )
            )
          )
        )
        (global.set $error_code (i32.const 6))
        (local.set $4 (i32.load (i32.const 1062312)))
        (br $block1 (i32.load (i32.const 1062352)))
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
