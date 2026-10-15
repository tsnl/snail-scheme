(func $function181 (type $6) (param $0 i64) (param $1 i32) (param $2 i32) (param $3 i64) (param $4 (ref null $type54)) (result i64)
  (local $5 i64)
  (local $6 i64)
  (local $scratch i64)
  (if (result i64)
   (i64.gt_s
    (local.get $0)
    (local.get $3)
   )
   (then
    (if
     (i32.eqz
      (global.get $ready544)
     )
     (then
      (unreachable)
     )
    )
    (if
     (i32.eqz
      (global.get $ready559)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (struct.get $type60 1
      (global.get $global559)
     )
    )
    (local.set $4
     (call $function156
      (call $foreign2
       (global.get $global544)
      )
      (block (result i64)
       (if
        (i32.eqz
         (global.get $ready545)
        )
        (then
         (unreachable)
        )
       )
       (if
        (i32.eqz
         (global.get $ready559)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (struct.get $type60 1
         (global.get $global559)
        )
       )
       (local.set $scratch
        (call $foreign2
         (global.get $global545)
        )
       )
       (if
        (i32.eqz
         (global.get $ready472)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global472)
        )
       )
       (local.get $scratch)
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
    (return_call $function181
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
    (if
     (i32.eqz
      (global.get $ready546)
     )
     (then
      (unreachable)
     )
    )
    (i64.extend_i32_u
     (i32.ne
      (if (result i32)
       (global.get $global546)
       (then
        (i32.const 0)
       )
       (else
        (if
         (i32.eqz
          (global.get $ready547)
         )
         (then
          (unreachable)
         )
        )
        (if
         (i32.eqz
          (global.get $ready148)
         )
         (then
          (unreachable)
         )
        )
        (drop
         (ref.as_non_null
          (global.get $global148)
         )
        )
        (call $function54
         (local.get $4)
         (global.get $global547)
        )
       )
      )
      (i32.const 0)
     )
    )
   )
  )
 )
