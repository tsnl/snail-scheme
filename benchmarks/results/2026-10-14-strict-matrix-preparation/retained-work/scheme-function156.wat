(func $function156 (type $call105) (param $0 i64) (param $1 i64) (result (ref null $type54))
  (local $2 i64)
  (local $3 (ref null $type32))
  (local $4 (ref $type103))
  (local $5 (ref $type46))
  (local $6 (ref $type33))
  (local $7 (ref $type33))
  (local $8 (ref null $type30))
  (local $9 (ref $type61))
  (local $10 (ref $type60))
  (local $11 (ref $type60))
  (if
   (i32.eqz
    (global.get $ready457)
   )
   (then
    (unreachable)
   )
  )
  (local.set $4
   (ref.as_non_null
    (global.get $global457)
   )
  )
  (if
   (i32.eqz
    (global.get $ready475)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global475)
   )
  )
  (if
   (i32.eqz
    (global.get $ready452)
   )
   (then
    (unreachable)
   )
  )
  (local.set $2
   (call $function150
    (struct.get $type33 1
     (global.get $global452)
    )
    (local.get $1)
   )
  )
  (if
   (i32.eqz
    (global.get $ready431)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (struct.get $type33 1
    (global.get $global431)
   )
  )
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
    (global.get $ready435)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global435)
   )
  )
  (local.set $2
   (if (result i64)
    (i64.lt_s
     (local.get $2)
     (i64.const 2)
    )
    (then
     (i64.const 2)
    )
    (else
     (call $function147
      (local.get $2)
      (local.tee $5
       (struct.new $type46
        (i64.const 2)
        (struct.new $type47
         (global.get $empty45)
        )
       )
      )
      (struct.new $type47
       (local.get $5)
      )
      (i32.const 0)
      (i32.const 0)
      (i32.const 1)
      (i64.const 3)
     )
    )
   )
  )
  (if
   (i32.eqz
    (global.get $ready406)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global406)
   )
  )
  (if
   (i32.eqz
    (global.get $ready333)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global333)
   )
  )
  (if
   (i32.eqz
    (global.get $ready408)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global408)
   )
  )
  (if
   (i32.eqz
    (global.get $ready283)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global283)
   )
  )
  (local.set $6
   (struct.new $type33
    (ref.func $function141)
    (struct.new $environment141
     (local.get $2)
     (call $function95
      (i64.sub
       (local.get $2)
       (i64.const 1)
      )
      (struct.new $type33
       (ref.func $function139)
       (struct.new $environment139
        (local.get $2)
       )
      )
     )
    )
   )
  )
  (if
   (i32.eqz
    (global.get $ready289)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global289)
   )
  )
  (if
   (i32.eqz
    (global.get $ready509)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global509)
   )
  )
  (local.set $8
   (struct.get $type32 0
    (local.tee $3
     (call $function65
      (call $function165
       (i64.sub
        (local.get $0)
        (i64.const 1)
       )
       (struct.new $type84
        (ref.func $primitive0)
        (ref.null none)
       )
       (ref.null none)
      )
      (block (result (ref (exact $type84)))
       (if
        (i32.eqz
         (global.get $ready184)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global184)
        )
       )
       (struct.new $type84
        (ref.func $function168)
        (ref.null none)
       )
      )
     )
    )
   )
  )
  (if
   (i32.eqz
    (global.get $ready239)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global239)
   )
  )
  (struct.get $type104 2
   (call $function169
    (local.get $1)
    (local.get $4)
    (struct.new $type93
     (struct.new $environment110
      (local.tee $9
       (struct.new $type61
        (ref.func $function135)
        (struct.new $environment135
         (local.get $2)
         (i32.const 0)
        )
       )
      )
      (local.tee $10
       (struct.new $type60
        (ref.func $function136)
        (struct.new $environment136
         (local.get $2)
        )
       )
      )
      (local.tee $7
       (struct.new $type33
        (ref.func $function137)
        (struct.new $environment137
         (local.get $2)
        )
       )
      )
      (local.tee $11
       (struct.new $type60
        (ref.func $function138)
        (struct.new $environment138
         (local.get $2)
        )
       )
      )
      (struct.new $type55
       (ref.func $function98)
       (struct.new $environment98
        (i64.const 0)
        (i64.const 1)
        (local.get $9)
        (local.get $10)
        (local.get $7)
        (local.get $11)
        (local.get $6)
       )
      )
     )
    )
    (i32.const 0)
    (i32.const 0)
    (i32.const 1)
    (i64.const 1)
    (struct.new $type32
     (local.get $8)
     (ref.null none)
    )
    (struct.get $type32 1
     (local.get $3)
    )
    (struct.new $type104
     (i64.const -1)
     (i64.const -1)
     (ref.null none)
    )
   )
  )
 )
