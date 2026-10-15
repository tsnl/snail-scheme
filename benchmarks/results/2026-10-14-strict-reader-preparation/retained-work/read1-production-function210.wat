(func $function210 (type $33) (param $0 i64) (param $1 i32) (param $2 i32) (param $3 i64) (param $4 (ref $type13)) (result i64)
  (local $5 (ref $type58))
  (local $6 (ref $type138))
  (local $7 (ref $type138))
  (local $8 (ref $type18))
  (local $9 (ref $type56))
  (local $10 i32)
  (local $scratch (ref $type18))
  (if (result i64)
   (i64.gt_s
    (local.get $0)
    (local.get $3)
   )
   (then
    (drop
     (ref.as_non_null
      (global.get $global758)
     )
    )
    (drop
     (call $function41
      (block (result (ref $type18))
       (local.set $scratch
        (ref.as_non_null
         (global.get $global755)
        )
       )
       (if
        (i32.eqz
         (call $foreign26)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global732)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global739)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global120)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global109)
        )
       )
       (local.get $scratch)
      )
     )
    )
    (local.set $5
     (struct.new $type58
      (struct.new $type56
       (call $snail:io/open-input-file)
      )
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global717)
     )
    )
    (local.set $6
     (call $function198
      (local.get $5)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global451)
     )
    )
    (local.set $4
     (if (result (ref $type13))
      (if (result i32)
       (local.tee $10
        (struct.get $type138 0
         (local.get $6)
        )
       )
       (then
        (if
         (i32.eq
          (local.get $10)
          (i32.const 1)
         )
         (then
          (drop
           (ref.cast (ref $type140)
            (local.get $6)
           )
          )
         )
         (else
          (drop
           (ref.cast (ref $type141)
            (local.get $6)
           )
          )
         )
        )
        (i32.const 0)
       )
       (else
        (i32.const 1)
       )
      )
      (then
       (struct.new $type15
        (i32.const 1)
        (i32.const 0)
       )
      )
      (else
       (drop
        (ref.as_non_null
         (global.get $global717)
        )
       )
       (local.set $7
        (call $function198
         (local.get $5)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global456)
        )
       )
       (call $function203
        (local.get $5)
        (i32.const 0)
        (i32.const 1)
        (local.get $7)
        (call $function135
         (local.get $6)
        )
        (i64.const 1)
       )
      )
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global127)
     )
    )
    (if
     (i32.eqz
      (global.get $ready124)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global124)
     )
    )
    (if
     (i32.ne
      (local.tee $10
       (struct.get $type56 0
        (local.tee $9
         (struct.get $type58 0
          (local.get $5)
         )
        )
       )
      )
      (i32.const -1)
     )
     (then
      (struct.set $type56 0
       (local.get $9)
       (i32.const -1)
      )
      (call $snail:io/close
       (local.get $10)
      )
     )
    )
    (if
     (i32.eqz
      (local.get $2)
     )
     (then
      (unreachable)
     )
    )
    (return_call $function210
     (local.get $0)
     (local.get $1)
     (local.get $2)
     (i64.add
      (local.get $3)
      (i64.const 1)
     )
     (local.get $4)
    )
   )
   (else
    (drop
     (ref.as_non_null
      (global.get $global424)
     )
    )
    (i64.extend_i32_u
     (i32.ne
      (call $function129
       (local.get $4)
       (ref.as_non_null
        (global.get $global756)
       )
      )
      (i32.const 0)
     )
    )
   )
  )
 )
