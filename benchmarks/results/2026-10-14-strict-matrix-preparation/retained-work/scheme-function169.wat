(func $function169 (type $14) (param $0 i64) (param $1 (ref $type103)) (param $2 (ref $type93)) (param $3 i32) (param $4 i32) (param $5 i32) (param $6 i64) (param $7 (ref $type32)) (param $8 (ref null $type32)) (param $9 (ref $type104)) (result (ref $type104))
  (local $10 (ref $environment110))
  (local $11 (ref $type32))
  (local $12 (ref $type55))
  (local $13 (ref $type109))
  (local $14 (ref null $type32))
  (local $15 (ref $type94))
  (local $16 i64)
  (local $17 i64)
  (local.set $15
   (if (result (ref $type94))
    (i64.gt_s
     (local.get $0)
     (local.get $6)
    )
    (then
     (struct.new $type94
      (ref.func $function111)
      (struct.new $environment111
       (struct.get $environment110 0
        (local.tee $10
         (struct.get $type93 0
          (local.get $2)
         )
        )
       )
       (struct.get $environment110 1
        (local.get $10)
       )
       (struct.get $environment110 2
        (local.get $10)
       )
       (struct.get $environment110 3
        (local.get $10)
       )
       (call_ref $call55
        (struct.get $type55 1
         (local.tee $12
          (struct.get $environment110 4
           (local.get $10)
          )
         )
        )
        (local.get $7)
        (struct.get $type55 0
         (local.get $12)
        )
       )
      )
     )
    )
    (else
     (if
      (i32.eqz
       (global.get $ready488)
      )
      (then
       (unreachable)
      )
     )
     (drop
      (ref.as_non_null
       (global.get $global488)
      )
     )
     (if
      (i32.eqz
       (global.get $ready462)
      )
      (then
       (unreachable)
      )
     )
     (drop
      (ref.as_non_null
       (global.get $global462)
      )
     )
     (local.set $13
      (struct.new $type109
       (ref.func $function159)
       (struct.new $environment159
        (local.get $2)
        (struct.get $type32 0
         (local.get $7)
        )
       )
      )
     )
     (struct.new $type94
      (ref.func $function163)
      (struct.new $environment163
       (if (result (ref null $type110))
        (i64.lt_s
         (local.tee $17
          (call $function153
           (local.tee $14
            (struct.get $type32 1
             (local.get $7)
            )
           )
          )
         )
         (local.tee $16
          (i64.sub
           (local.get $0)
           (i64.const 2)
          )
         )
        )
        (then
         (ref.null none)
        )
        (else
         (call $function161
          (i32.const 0)
          (i32.const 1)
          (local.get $16)
          (local.get $14)
          (local.get $13)
          (i64.sub
           (local.get $17)
           (local.get $16)
          )
          (ref.null none)
         )
        )
       )
      )
     )
    )
   )
  )
  (if
   (i32.eqz
    (global.get $ready525)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global525)
   )
  )
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
  (local.set $8
   (call $function65
    (local.get $8)
    (struct.new $type84
     (ref.func $function171)
     (struct.new $environment171
      (local.get $15)
     )
    )
   )
  )
  (if
   (i32.eqz
    (global.get $ready269)
   )
   (then
    (unreachable)
   )
  )
  (if
   (ref.is_null
    (local.tee $8
     (call $function91
      (struct.get $type55 1
       (global.get $global269)
      )
      (local.get $8)
     )
    )
   )
   (then
    (if
     (i32.eqz
      (global.get $ready269)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (struct.get $type55 1
      (global.get $global269)
     )
    )
    (local.set $11
     (struct.new $type32
      (struct.get $type32 0
       (local.get $7)
      )
      (ref.null none)
     )
    )
    (return_call $function152
     (if (result (ref null $type32))
      (ref.is_null
       (local.tee $8
        (struct.get $type32 1
         (local.get $7)
        )
       )
      )
      (then
       (local.get $11)
      )
      (else
       (local.set $7
        (struct.new $type32
         (struct.get $type32 0
          (local.get $8)
         )
         (local.get $11)
        )
       )
       (if (result (ref null $type32))
        (ref.is_null
         (local.tee $8
          (struct.get $type32 1
           (local.get $8)
          )
         )
        )
        (then
         (local.get $7)
        )
        (else
         (local.set $7
          (struct.new $type32
           (struct.get $type32 0
            (local.get $8)
           )
           (local.get $7)
          )
         )
         (if (result (ref null $type32))
          (ref.is_null
           (local.tee $8
            (struct.get $type32 1
             (local.get $8)
            )
           )
          )
          (then
           (local.get $7)
          )
          (else
           (local.set $7
            (struct.new $type32
             (struct.get $type32 0
              (local.get $8)
             )
             (local.get $7)
            )
           )
           (if (result (ref null $type32))
            (ref.is_null
             (local.tee $8
              (struct.get $type32 1
               (local.get $8)
              )
             )
            )
            (then
             (local.get $7)
            )
            (else
             (local.set $7
              (struct.new $type32
               (struct.get $type32 0
                (local.get $8)
               )
               (local.get $7)
              )
             )
             (if (result (ref null $type32))
              (ref.is_null
               (local.tee $8
                (struct.get $type32 1
                 (local.get $8)
                )
               )
              )
              (then
               (local.get $7)
              )
              (else
               (local.set $7
                (struct.new $type32
                 (struct.get $type32 0
                  (local.get $8)
                 )
                 (local.get $7)
                )
               )
               (if (result (ref null $type32))
                (ref.is_null
                 (local.tee $8
                  (struct.get $type32 1
                   (local.get $8)
                  )
                 )
                )
                (then
                 (local.get $7)
                )
                (else
                 (local.set $7
                  (struct.new $type32
                   (struct.get $type32 0
                    (local.get $8)
                   )
                   (local.get $7)
                  )
                 )
                 (if (result (ref null $type32))
                  (ref.is_null
                   (local.tee $8
                    (struct.get $type32 1
                     (local.get $8)
                    )
                   )
                  )
                  (then
                   (local.get $7)
                  )
                  (else
                   (local.set $7
                    (struct.new $type32
                     (struct.get $type32 0
                      (local.get $8)
                     )
                     (local.get $7)
                    )
                   )
                   (if (result (ref null $type32))
                    (ref.is_null
                     (local.tee $8
                      (struct.get $type32 1
                       (local.get $8)
                      )
                     )
                    )
                    (then
                     (local.get $7)
                    )
                    (else
                     (call $function92
                      (i32.const 0)
                      (i32.const 1)
                      (struct.get $type32 1
                       (local.get $8)
                      )
                      (struct.new $type32
                       (struct.get $type32 0
                        (local.get $8)
                       )
                       (local.get $7)
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
     (local.get $9)
    )
   )
   (else
    (return_call $function172
     (local.get $0)
     (local.get $1)
     (local.get $2)
     (local.get $3)
     (local.get $4)
     (local.get $5)
     (local.get $6)
     (local.get $7)
     (i32.const 0)
     (i32.const 1)
     (local.get $8)
     (local.get $9)
    )
   )
  )
  (unreachable)
 )
