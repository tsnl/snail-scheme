(func $function150 (type $call33) (param $0 structref) (param $1 i64) (result i64)
  (local $2 i64)
  (if
   (i32.eqz
    (global.get $ready159)
   )
   (then
    (unreachable)
   )
  )
  (local.set $2
   (call $function59
    (struct.get $type60 1
     (global.get $global159)
    )
    (local.get $1)
    (i64.const 2)
   )
  )
  (if
   (i32.eqz
    (global.get $ready125)
   )
   (then
    (unreachable)
   )
  )
  (local.set $2
   (call $function46
    (struct.get $type60 1
     (global.get $global125)
    )
    (local.get $1)
    (local.get $2)
   )
  )
  (if
   (i32.eqz
    (global.get $ready123)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (struct.get $type61 1
    (global.get $global123)
   )
  )
  (if (result i64)
   (i64.eqz
    (i64.and
     (local.get $1)
     (i64.const 1)
    )
   )
   (then
    (local.get $2)
   )
   (else
    (i64.mul
     (if (result i64)
      (i64.le_s
       (local.get $1)
       (i64.const 0)
      )
      (then
       (i64.const 0)
      )
      (else
       (if (result i64)
        (i64.le_s
         (local.get $1)
         (i64.const 1)
        )
        (then
         (i64.const 1)
        )
        (else
         (if (result i64)
          (i64.le_s
           (local.get $1)
           (i64.const 4)
          )
          (then
           (i64.const 2)
          )
          (else
           (if (result i64)
            (i64.le_s
             (local.get $1)
             (i64.const 9)
            )
            (then
             (i64.const 3)
            )
            (else
             (if (result i64)
              (i64.le_s
               (local.get $1)
               (i64.const 16)
              )
              (then
               (i64.const 4)
              )
              (else
               (if (result i64)
                (i64.le_s
                 (local.get $1)
                 (i64.const 25)
                )
                (then
                 (i64.const 5)
                )
                (else
                 (if (result i64)
                  (i64.le_s
                   (local.get $1)
                   (i64.const 36)
                  )
                  (then
                   (i64.const 6)
                  )
                  (else
                   (if (result i64)
                    (i64.le_s
                     (local.get $1)
                     (i64.const 49)
                    )
                    (then
                     (i64.const 7)
                    )
                    (else
                     (if (result i64)
                      (i64.le_s
                       (local.get $1)
                       (i64.const 64)
                      )
                      (then
                       (i64.const 8)
                      )
                      (else
                       (if (result i64)
                        (i64.le_s
                         (local.get $1)
                         (i64.const 81)
                        )
                        (then
                         (i64.const 9)
                        )
                        (else
                         (call $function151
                          (local.get $1)
                          (i32.const 0)
                          (i32.const 1)
                          (i64.const 10)
                         )
                        )
                       )
                      )
                     )
                    )
                   )
                  )
                 )
                )
               )
              )
             )
            )
           )
          )
         )
        )
       )
      )
     )
     (local.get $2)
    )
   )
  )
 )
