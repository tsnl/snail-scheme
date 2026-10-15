(func $function92 (type $67) (param $0 i32) (param $1 i32) (param $2 (ref null $type32)) (param $3 (ref $type32)) (result (ref null $type32))
  (local $4 (ref null $type32))
  (local $5 (ref null $type30))
  (if (result (ref $type32))
   (ref.is_null
    (local.get $2)
   )
   (then
    (local.get $3)
   )
   (else
    (local.set $4
     (struct.get $type32 1
      (local.get $2)
     )
    )
    (local.set $5
     (struct.get $type32 0
      (local.get $2)
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
    (return_call $function92
     (local.get $0)
     (local.get $1)
     (local.get $4)
     (struct.new $type32
      (local.get $5)
      (local.get $3)
     )
    )
   )
  )
 )
