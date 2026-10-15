(func $function135 (type $call142) (param $0 (ref $type138)) (result (ref $type13))
  (local $1 (ref $type18))
  (local $scratch (ref $type18))
  (if (result (ref $type13))
   (i32.eq
    (struct.get $type138 0
     (local.get $0)
    )
    (i32.const 1)
   )
   (then
    (struct.get $type140 1
     (ref.cast (ref $type140)
      (local.get $0)
     )
    )
   )
   (else
    (if
     (struct.get $type138 0
      (local.get $0)
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
               (local.get $0)
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
      (call $snail:datum/fail
       (call $function104
        (global.get $string2)
       )
      )
      (unreachable)
     )
    )
    (unreachable)
   )
  )
 )
