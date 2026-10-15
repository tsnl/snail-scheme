(func $function198 (type $call143) (param $0 (ref $type58)) (result (ref $type138))
  (local $1 (ref $type138))
  (local $2 (ref $type159))
  (local $3 (ref $type18))
  (local $scratch (ref $type18))
  (drop
   (ref.as_non_null
    (global.get $global461)
   )
  )
  (if
   (i32.eqz
    (global.get $ready463)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global463)
   )
  )
  (local.set $2
   (call $function137
    (local.get $0)
   )
  )
  (if
   (i32.eqz
    (global.get $ready631)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global631)
   )
  )
  (if (result (ref $type138))
   (i32.eq
    (struct.get $type138 0
     (local.tee $1
      (call $function180
       (local.get $0)
       (local.get $2)
      )
     )
    )
    (i32.const 2)
   )
   (then
    (drop
     (ref.as_non_null
      (global.get $global90)
     )
    )
    (call $snail:datum/fail
     (call $function104
      (block (result (ref $type18))
       (local.set $scratch
        (call $function35
         (struct.new $type48
          (global.get $string1)
          (struct.new $type48
           (struct.get $type141 1
            (ref.cast (ref $type141)
             (local.get $1)
            )
           )
           (ref.null none)
          )
         )
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global323)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global317)
        )
       )
       (local.get $scratch)
      )
     )
    )
    (unreachable)
   )
   (else
    (if
     (i32.eq
      (struct.get $type138 0
       (local.get $1)
      )
      (i32.const 1)
     )
     (then
      (drop
       (ref.cast (ref $type140)
        (local.get $1)
       )
      )
     )
    )
    (local.get $1)
   )
  )
 )
