(func $function161 (type $22) (param $0 i32) (param $1 i32) (param $2 i64) (param $3 (ref null $type32)) (param $4 (ref $type109)) (param $5 i64) (param $6 (ref null $type110)) (result (ref null $type110))
  (local $7 (ref null $type30))
  (if
   (i32.eqz
    (global.get $ready368)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (struct.get $type61 1
    (global.get $global368)
   )
  )
  (if
   (i64.eqz
    (local.get $5)
   )
   (then
    (return_call_ref $call109
     (struct.get $type109 1
      (local.get $4)
     )
     (local.get $3)
     (local.get $6)
     (struct.get $type109 0
      (local.get $4)
     )
    )
   )
   (else
    (if
     (i32.eqz
      (global.get $ready368)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (struct.get $type61 1
      (global.get $global368)
     )
    )
    (if
     (i64.eqz
      (local.get $2)
     )
     (then
      (return_call_ref $call109
       (struct.get $type109 1
        (local.get $4)
       )
       (ref.null none)
       (local.get $6)
       (struct.get $type109 0
        (local.get $4)
       )
      )
     )
     (else
      (local.set $7
       (struct.get $type32 0
        (local.get $3)
       )
      )
      (local.set $3
       (struct.get $type32 1
        (local.get $3)
       )
      )
      (if
       (i32.eqz
        (local.get $1)
       )
       (then
        (unreachable)
       )
      )
      (local.set $6
       (call $function161
        (local.get $0)
        (local.get $1)
        (i64.sub
         (local.get $2)
         (i64.const 1)
        )
        (local.get $3)
        (struct.new $type109
         (ref.func $function162)
         (struct.new $environment162
          (local.get $4)
          (local.get $7)
         )
        )
        (local.get $5)
        (local.get $6)
       )
      )
      (if
       (i32.eqz
        (local.get $1)
       )
       (then
        (unreachable)
       )
      )
      (return_call $function161
       (local.get $0)
       (local.get $1)
       (local.get $2)
       (local.get $3)
       (local.get $4)
       (i64.sub
        (local.get $5)
        (i64.const 1)
       )
       (local.get $6)
      )
     )
    )
    (unreachable)
   )
  )
  (unreachable)
 )
