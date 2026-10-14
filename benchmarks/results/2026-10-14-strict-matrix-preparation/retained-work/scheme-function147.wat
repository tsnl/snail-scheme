(func $function147 (type $35) (param $0 i64) (param $1 (ref $type44)) (param $2 (ref $type47)) (param $3 i32) (param $4 i32) (param $5 i32) (param $6 i64) (result i64)
  (local $7 (ref $type44))
  (local $8 (ref $type46))
  (block $block
   (return
    (if (result i64)
     (call $function146
      (local.get $6)
      (i32.const 0)
      (i32.const 1)
      (local.get $1)
     )
     (then
      (if
       (i32.eqz
        (global.get $ready131)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global131)
       )
      )
      (if
       (i32.eqz
        (global.get $ready447)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global447)
       )
      )
      (if
       (i32.eqz
        (global.get $ready136)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global136)
       )
      )
      (if
       (ref.test (ref $type45)
        (local.tee $7
         (struct.get $type47 0
          (local.get $2)
         )
        )
       )
       (then
        (unreachable)
       )
      )
      (struct.set $type47 0
       (struct.get $type46 1
        (ref.cast (ref $type46)
         (local.get $7)
        )
       )
       (local.tee $8
        (struct.new $type46
         (local.get $6)
         (struct.new $type47
          (global.get $empty45)
         )
        )
       )
      )
      (if
       (i32.eqz
        (global.get $ready449)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global449)
       )
      )
      (struct.set $type47 0
       (local.get $2)
       (local.get $8)
      )
      (br_if $block
       (i64.ge_s
        (local.get $0)
        (local.get $6)
       )
      )
      (local.get $6)
     )
     (else
      (br $block)
     )
    )
   )
  )
  (if
   (i32.eqz
    (local.get $5)
   )
   (then
    (unreachable)
   )
  )
  (return_call $function147
   (local.get $0)
   (local.get $1)
   (local.get $2)
   (local.get $3)
   (local.get $4)
   (local.get $5)
   (i64.add
    (local.get $6)
    (i64.const 2)
   )
  )
 )
