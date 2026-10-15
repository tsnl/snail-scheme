(func $function210 (type $33) (param $0 i64) (param $1 i32) (param $2 i32) (param $3 i64) (param $4 (ref $type13)) (result i64)
  (local $5 f64)
  (local $6 i32)
  (local $7 (ref $type58))
  (local $8 (ref $type18))
  (local $9 (ref $type56))
  (local $scratch (ref $type18))
  (if (result i64)
   (i64.gt_s
    (local.get $0)
    (local.get $3)
   )
   (then
    (drop
     (ref.as_non_null
      (global.get $global759)
     )
    )
    (drop
     (call $function41
      (block (result (ref $type18))
       (local.set $scratch
        (ref.as_non_null
         (global.get $global756)
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
         (global.get $global738)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global740)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global736)
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
    (local.set $7
     (struct.new $type58
      (struct.new $type56
       (call $snail:io/open-input-file)
      )
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global732)
     )
    )
    (local.set $5
     (call $function201
      (local.get $7)
      (f64.const 0)
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
      (local.tee $6
       (struct.get $type56 0
        (local.tee $9
         (struct.get $type58 0
          (local.get $7)
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
       (local.get $6)
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
     (struct.new $type23
      (i32.const 5)
      (struct.new $type26
       (i32.const 1)
       (local.get $5)
      )
     )
    )
   )
   (else
    (drop
     (ref.as_non_null
      (global.get $global723)
     )
    )
    (local.set $5
     (f64.sub
      (call $function199
       (local.get $4)
      )
      (block (result f64)
       (drop
        (ref.as_non_null
         (global.get $global723)
        )
       )
       (call $function199
        (ref.as_non_null
         (global.get $global757)
        )
       )
      )
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global715)
     )
    )
    (i64.extend_i32_u
     (f64.le
      (select
       (f64.sub
        (f64.const 0)
        (local.get $5)
       )
       (local.get $5)
       (f64.lt
        (local.get $5)
        (f64.const 0)
       )
      )
      (f64.const 1e-09)
     )
    )
   )
  )
 )
