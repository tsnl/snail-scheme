(func $function91 (type $call55) (param $0 (ref null $environment98)) (param $1 (ref null $type32)) (result (ref null $type32))
  (local $2 (ref $type32))
  (if (result (ref null $type32))
   (ref.is_null
    (local.get $1)
   )
   (then
    (ref.null none)
   )
   (else
    (local.set $2
     (struct.new $type32
      (struct.get $type32 0
       (local.get $1)
      )
      (ref.null none)
     )
    )
    (if (result (ref $type32))
     (ref.is_null
      (local.tee $1
       (struct.get $type32 1
        (local.get $1)
       )
      )
     )
     (then
      (local.get $2)
     )
     (else
      (local.set $2
       (struct.new $type32
        (struct.get $type32 0
         (local.get $1)
        )
        (local.get $2)
       )
      )
      (if (result (ref $type32))
       (ref.is_null
        (local.tee $1
         (struct.get $type32 1
          (local.get $1)
         )
        )
       )
       (then
        (local.get $2)
       )
       (else
        (local.set $2
         (struct.new $type32
          (struct.get $type32 0
           (local.get $1)
          )
          (local.get $2)
         )
        )
        (if (result (ref $type32))
         (ref.is_null
          (local.tee $1
           (struct.get $type32 1
            (local.get $1)
           )
          )
         )
         (then
          (local.get $2)
         )
         (else
          (local.set $2
           (struct.new $type32
            (struct.get $type32 0
             (local.get $1)
            )
            (local.get $2)
           )
          )
          (if (result (ref $type32))
           (ref.is_null
            (local.tee $1
             (struct.get $type32 1
              (local.get $1)
             )
            )
           )
           (then
            (local.get $2)
           )
           (else
            (local.set $2
             (struct.new $type32
              (struct.get $type32 0
               (local.get $1)
              )
              (local.get $2)
             )
            )
            (if (result (ref $type32))
             (ref.is_null
              (local.tee $1
               (struct.get $type32 1
                (local.get $1)
               )
              )
             )
             (then
              (local.get $2)
             )
             (else
              (local.set $2
               (struct.new $type32
                (struct.get $type32 0
                 (local.get $1)
                )
                (local.get $2)
               )
              )
              (if (result (ref $type32))
               (ref.is_null
                (local.tee $1
                 (struct.get $type32 1
                  (local.get $1)
                 )
                )
               )
               (then
                (local.get $2)
               )
               (else
                (local.set $2
                 (struct.new $type32
                  (struct.get $type32 0
                   (local.get $1)
                  )
                  (local.get $2)
                 )
                )
                (if (result (ref $type32))
                 (ref.is_null
                  (local.tee $1
                   (struct.get $type32 1
                    (local.get $1)
                   )
                  )
                 )
                 (then
                  (local.get $2)
                 )
                 (else
                  (local.set $2
                   (struct.new $type32
                    (struct.get $type32 0
                     (local.get $1)
                    )
                    (local.get $2)
                   )
                  )
                  (if (result (ref $type32))
                   (ref.is_null
                    (local.tee $1
                     (struct.get $type32 1
                      (local.get $1)
                     )
                    )
                   )
                   (then
                    (local.get $2)
                   )
                   (else
                    (return_call $function92
                     (i32.const 0)
                     (i32.const 1)
                     (struct.get $type32 1
                      (local.get $1)
                     )
                     (struct.new $type32
                      (struct.get $type32 0
                       (local.get $1)
                      )
                      (local.get $2)
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
