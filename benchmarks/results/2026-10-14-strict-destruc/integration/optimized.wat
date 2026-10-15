(module
 (rec
  (type $type36 (sub (struct)))
  (type $type31 (sub (struct)))
  (type $type27 (sub (struct)))
  (type $3 (func (param i64 i32 i32 i64 (ref $type36)) (result i64)))
  (type $call63 (func (param i64) (result (ref null $type55))))
  (type $call64 (func (param i64) (result (ref null $type57))))
  (type $call62 (func (result (ref $type27))))
  (type $7 (func (param i64 i32 i32 i64 (ref $type31)) (result (ref $type31))))
  (type $8 (func (param i32 i32 (ref $type31) i64) (result i64)))
  (type $9 (func (param i64 i32 i32 (ref $type36) (ref $type36)) (result i32)))
  (type $10 (func (param (ref $type31) (ref $type31) i32 i32 (ref $type31) (ref $type31)) (result (ref $type31))))
  (type $11 (func (param i32 i32 i64 (ref $type33)) (result (ref $type31))))
  (type $12 (func (param (ref $type28) (ref $type33)) (result (ref $type33))))
  (type $13 (func (param i64 i32 i32 (ref $type36)) (result i32)))
  (type $14 (func (param i64 (ref $type36) i32 i32 i64) (result (ref $type36))))
  (type $15 (func (param (ref $type32) (ref $type38)) (result (ref $type38))))
  (type $16 (func (param i32 i32 i64 (ref $type38)) (result (ref $type36))))
  (type $type37 (sub $type36 (struct)))
  (type $type32 (sub $type31 (struct)))
  (type $call60 (func (param i64 i64) (result (ref $type36))))
  (type $type39 (struct (field (ref $type36))))
  (type $type38 (sub $type36 (struct (field (ref $type35)) (field (ref $type39)))))
  (type $call56 (func (param (ref $type36) (ref null $type57)) (result i32)))
  (type $type35 (struct (field (mut (ref $type31)))))
  (type $type29 (sub $type27 (struct (field i64))))
  (type $type55 (struct (field (ref $type27)) (field (ref null $type55))))
  (type $type34 (struct (field (mut (ref $type27)))))
  (type $type33 (sub $type31 (struct (field (ref $type34)) (field (ref $type35)))))
  (type $call54 (func (param (ref $type31) (ref null $type55)) (result i32)))
  (type $type65 (struct))
  (type $type57 (struct (field (ref null $type55)) (field (ref null $type57))))
  (type $type64 (struct))
  (type $type63 (struct))
  (type $type62 (struct))
  (type $type5 (struct))
  (type $type61 (struct (field (mut i64))))
  (type $type60 (struct))
  (type $type59 (struct))
  (type $type58 (struct))
  (type $type56 (struct))
  (type $type54 (struct))
  (type $type53 (struct))
  (type $type52 (struct))
  (type $type51 (struct))
  (type $type50 (struct))
  (type $type49 (struct))
  (type $type48 (struct))
  (type $type47 (struct))
  (type $type46 (struct))
  (type $type45 (struct))
  (type $type44 (struct))
  (type $type43 (struct))
  (type $type42 (struct))
  (type $type41 (struct))
  (type $type40 (struct))
  (type $type30 (struct))
  (type $type28 (sub $type27 (struct)))
 )
 (type $57 (func (param i64) (result i64)))
 (type $58 (func (param i32) (result i64)))
 (type $59 (func))
 (import "benchmark" "expected_i64" (func $foreign0 (param i64) (result i64)))
 (import "benchmark" "hide_i64" (func $foreign1 (param i64) (result i64)))
 (import "benchmark" "input_i64" (func $foreign2 (param i32) (result i64)))
 (global $execution (mut i32) (i32.const 0))
 (global $global109 (mut (ref null $type28)) (ref.null none))
 (global $ready109 (mut i32) (i32.const 0))
 (global $global148 (mut (ref null $type30)) (ref.null none))
 (global $ready148 (mut i32) (i32.const 0))
 (global $global155 (mut (ref null $type40)) (ref.null none))
 (global $ready155 (mut i32) (i32.const 0))
 (global $global120 (mut (ref null $type41)) (ref.null none))
 (global $ready120 (mut i32) (i32.const 0))
 (global $global132 (mut (ref null $type42)) (ref.null none))
 (global $ready132 (mut i32) (i32.const 0))
 (global $global125 (mut (ref null $type43)) (ref.null none))
 (global $ready125 (mut i32) (i32.const 0))
 (global $global137 (mut (ref null $type44)) (ref.null none))
 (global $ready137 (mut i32) (i32.const 0))
 (global $global127 (mut (ref null $type45)) (ref.null none))
 (global $ready127 (mut i32) (i32.const 0))
 (global $global139 (mut (ref null $type46)) (ref.null none))
 (global $ready139 (mut i32) (i32.const 0))
 (global $global158 (mut (ref null $type47)) (ref.null none))
 (global $ready158 (mut i32) (i32.const 0))
 (global $global187 (mut (ref null $type48)) (ref.null none))
 (global $ready187 (mut i32) (i32.const 0))
 (global $global170 (mut (ref null $type49)) (ref.null none))
 (global $ready170 (mut i32) (i32.const 0))
 (global $global110 (mut (ref null $type50)) (ref.null none))
 (global $ready110 (mut i32) (i32.const 0))
 (global $global194 (mut (ref null $type51)) (ref.null none))
 (global $ready194 (mut i32) (i32.const 0))
 (global $global178 (mut (ref null $type52)) (ref.null none))
 (global $ready178 (mut i32) (i32.const 0))
 (global $global114 (mut (ref null $type53)) (ref.null none))
 (global $ready114 (mut i32) (i32.const 0))
 (global $global117 (mut (ref null $type54)) (ref.null none))
 (global $ready117 (mut i32) (i32.const 0))
 (global $global129 (mut (ref null $type56)) (ref.null none))
 (global $ready129 (mut i32) (i32.const 0))
 (global $global212 (mut (ref null $type58)) (ref.null none))
 (global $ready212 (mut i32) (i32.const 0))
 (global $global164 (mut (ref null $type59)) (ref.null none))
 (global $ready164 (mut i32) (i32.const 0))
 (global $global141 (mut (ref null $type60)) (ref.null none))
 (global $ready141 (mut i32) (i32.const 0))
 (global $global196 (mut (ref null $type61)) (ref.null none))
 (global $ready196 (mut i32) (i32.const 0))
 (global $global197 (mut (ref null $type5)) (ref.null none))
 (global $ready197 (mut i32) (i32.const 0))
 (global $global199 (mut (ref null $type62)) (ref.null none))
 (global $ready199 (mut i32) (i32.const 0))
 (global $global207 (mut (ref null $type63)) (ref.null none))
 (global $ready207 (mut i32) (i32.const 0))
 (global $global204 (mut (ref null $type64)) (ref.null none))
 (global $ready204 (mut i32) (i32.const 0))
 (global $global200 (mut i64) (i64.const 0))
 (global $ready200 (mut i32) (i32.const 0))
 (global $global201 (mut i64) (i64.const 0))
 (global $ready201 (mut i32) (i32.const 0))
 (global $global202 (mut i32) (i32.const 0))
 (global $ready202 (mut i32) (i32.const 0))
 (global $global203 (mut (ref null $type57)) (ref.null none))
 (global $ready203 (mut i32) (i32.const 0))
 (global $global210 (mut (ref null $type65)) (ref.null none))
 (global $ready210 (mut i32) (i32.const 0))
 (export "bench" (func $export0))
 (export "main" (func $main))
 (func $function43 (type $call54) (param $0 (ref $type31)) (param $1 (ref null $type55)) (result i32)
  (local $2 (ref $type27))
  (local $3 (ref $type27))
  (local $4 i64)
  (local $scratch (ref null $type55))
  (if
   (i32.eqz
    (global.get $ready120)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global120)
   )
  )
  (if (result i32)
   (if (result i32)
    (ref.test (ref $type33)
     (local.get $0)
    )
    (then
     (drop
      (ref.cast (ref $type33)
       (local.get $0)
      )
     )
     (i32.const 0)
    )
    (else
     (i32.const 1)
    )
   )
   (then
    (ref.is_null
     (local.get $1)
    )
   )
   (else
    (if (result i32)
     (ref.is_null
      (local.get $1)
     )
     (then
      (i32.const 0)
     )
     (else
      (if
       (i32.eqz
        (global.get $ready125)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global125)
       )
      )
      (if
       (i32.eqz
        (ref.test (ref $type33)
         (local.get $0)
        )
       )
       (then
        (unreachable)
       )
      )
      (local.set $3
       (struct.get $type34 0
        (struct.get $type33 0
         (ref.cast (ref $type33)
          (local.get $0)
         )
        )
       )
      )
      (local.set $2
       (struct.get $type55 0
        (local.get $1)
       )
      )
      (if
       (i32.eqz
        (global.get $ready114)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global114)
       )
      )
      (if
       (i32.eqz
        (global.get $ready110)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global110)
       )
      )
      (if (result i32)
       (if (result i32)
        (if (result i32)
         (ref.test (ref $type28)
          (local.get $3)
         )
         (then
          (i32.const 1)
         )
         (else
          (drop
           (ref.cast (ref $type29)
            (local.get $3)
           )
          )
          (i32.const 0)
         )
        )
        (then
         (if
          (i32.eqz
           (global.get $ready110)
          )
          (then
           (unreachable)
          )
         )
         (drop
          (ref.as_non_null
           (global.get $global110)
          )
         )
         (if (result i32)
          (ref.test (ref $type28)
           (local.get $2)
          )
          (then
           (i32.const 1)
          )
          (else
           (drop
            (ref.cast (ref $type29)
             (local.get $2)
            )
           )
           (i32.const 0)
          )
         )
        )
        (else
         (if
          (i32.eqz
           (global.get $ready110)
          )
          (then
           (unreachable)
          )
         )
         (drop
          (ref.as_non_null
           (global.get $global110)
          )
         )
         (if (result i32)
          (if (result i32)
           (ref.test (ref $type28)
            (local.get $2)
           )
           (then
            (i32.const 1)
           )
           (else
            (drop
             (ref.cast (ref $type29)
              (local.get $2)
             )
            )
            (i32.const 0)
           )
          )
          (then
           (i32.const 0)
          )
          (else
           (if
            (ref.test (ref $type28)
             (local.get $3)
            )
            (then
             (unreachable)
            )
           )
           (local.set $4
            (struct.get $type29 0
             (ref.cast (ref $type29)
              (local.get $3)
             )
            )
           )
           (if
            (ref.test (ref $type28)
             (local.get $2)
            )
            (then
             (unreachable)
            )
           )
           (i64.eq
            (struct.get $type29 0
             (ref.cast (ref $type29)
              (local.get $2)
             )
            )
            (local.get $4)
           )
          )
         )
        )
       )
       (then
        (if
         (i32.eqz
          (global.get $ready127)
         )
         (then
          (unreachable)
         )
        )
        (drop
         (ref.as_non_null
          (global.get $global127)
         )
        )
        (if
         (i32.eqz
          (ref.test (ref $type33)
           (local.get $0)
          )
         )
         (then
          (unreachable)
         )
        )
        (return_call $function43
         (struct.get $type35 0
          (struct.get $type33 1
           (ref.cast (ref $type33)
            (local.get $0)
           )
          )
         )
         (block (result (ref null $type55))
          (local.set $scratch
           (struct.get $type55 1
            (local.get $1)
           )
          )
          (if
           (i32.eqz
            (global.get $ready117)
           )
           (then
            (unreachable)
           )
          )
          (drop
           (ref.as_non_null
            (global.get $global117)
           )
          )
          (local.get $scratch)
         )
        )
       )
       (else
        (i32.const 0)
       )
      )
     )
    )
   )
  )
 )
 (func $function47 (type $call56) (param $0 (ref $type36)) (param $1 (ref null $type57)) (result i32)
  (local $2 (ref $type31))
  (local $3 (ref null $type55))
  (local $scratch (ref null $type55))
  (local $scratch_5 (ref null $type57))
  (if
   (i32.eqz
    (global.get $ready132)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global132)
   )
  )
  (if (result i32)
   (if (result i32)
    (ref.test (ref $type38)
     (local.get $0)
    )
    (then
     (drop
      (ref.cast (ref $type38)
       (local.get $0)
      )
     )
     (i32.const 0)
    )
    (else
     (i32.const 1)
    )
   )
   (then
    (ref.is_null
     (local.get $1)
    )
   )
   (else
    (if (result i32)
     (ref.is_null
      (local.get $1)
     )
     (then
      (i32.const 0)
     )
     (else
      (if
       (i32.eqz
        (global.get $ready137)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global137)
       )
      )
      (if
       (i32.eqz
        (ref.test (ref $type38)
         (local.get $0)
        )
       )
       (then
        (unreachable)
       )
      )
      (if (result i32)
       (call $function43
        (struct.get $type35 0
         (struct.get $type38 0
          (ref.cast (ref $type38)
           (local.get $0)
          )
         )
        )
        (block (result (ref null $type55))
         (local.set $scratch
          (struct.get $type57 0
           (local.get $1)
          )
         )
         (if
          (i32.eqz
           (global.get $ready117)
          )
          (then
           (unreachable)
          )
         )
         (drop
          (ref.as_non_null
           (global.get $global117)
          )
         )
         (local.get $scratch)
        )
       )
       (then
        (if
         (i32.eqz
          (global.get $ready139)
         )
         (then
          (unreachable)
         )
        )
        (drop
         (ref.as_non_null
          (global.get $global139)
         )
        )
        (if
         (i32.eqz
          (ref.test (ref $type38)
           (local.get $0)
          )
         )
         (then
          (unreachable)
         )
        )
        (return_call $function47
         (struct.get $type39 0
          (struct.get $type38 1
           (ref.cast (ref $type38)
            (local.get $0)
           )
          )
         )
         (block (result (ref null $type57))
          (local.set $scratch_5
           (struct.get $type57 1
            (local.get $1)
           )
          )
          (if
           (i32.eqz
            (global.get $ready129)
           )
           (then
            (unreachable)
           )
          )
          (drop
           (ref.as_non_null
            (global.get $global129)
           )
          )
          (local.get $scratch_5)
         )
        )
       )
       (else
        (i32.const 0)
       )
      )
     )
    )
   )
  )
 )
 (func $function51 (type $call60) (param $0 i64) (param $1 i64) (result (ref $type36))
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
  (return_call $function54
   (local.get $1)
   (struct.new $type38
    (struct.new $type35
     (struct.new_default $type32)
    )
    (struct.new $type39
     (struct.new $type38
      (struct.new $type35
       (struct.new_default $type32)
      )
      (struct.new $type39
       (struct.new $type38
        (struct.new $type35
         (struct.new_default $type32)
        )
        (struct.new $type39
         (struct.new $type38
          (struct.new $type35
           (struct.new_default $type32)
          )
          (struct.new $type39
           (struct.new $type38
            (struct.new $type35
             (struct.new_default $type32)
            )
            (struct.new $type39
             (struct.new $type38
              (struct.new $type35
               (struct.new_default $type32)
              )
              (struct.new $type39
               (struct.new $type38
                (struct.new $type35
                 (struct.new_default $type32)
                )
                (struct.new $type39
                 (struct.new $type38
                  (struct.new $type35
                   (struct.new_default $type32)
                  )
                  (struct.new $type39
                   (struct.new $type38
                    (struct.new $type35
                     (struct.new_default $type32)
                    )
                    (struct.new $type39
                     (struct.new $type38
                      (struct.new $type35
                       (struct.new_default $type32)
                      )
                      (struct.new $type39
                       (struct.new_default $type37)
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
   (i32.const 0)
   (i32.const 1)
   (local.get $0)
  )
 )
 (func $function54 (type $14) (param $0 i64) (param $1 (ref $type36)) (param $2 i32) (param $3 i32) (param $4 i64) (result (ref $type36))
  (local $5 (ref $type31))
  (local $6 (ref $type38))
  (if (result (ref $type36))
   (i64.eqz
    (local.get $4)
   )
   (then
    (local.get $1)
   )
   (else
    (if
     (i32.eqz
      (global.get $ready137)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global137)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type38)
       (local.get $1)
      )
     )
     (then
      (unreachable)
     )
    )
    (local.set $5
     (struct.get $type35 0
      (struct.get $type38 0
       (ref.cast (ref $type38)
        (local.get $1)
       )
      )
     )
    )
    (if
     (i32.eqz
      (global.get $ready120)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global120)
     )
    )
    (drop
     (if (result i32)
      (if (result i32)
       (ref.test (ref $type33)
        (local.get $5)
       )
       (then
        (drop
         (ref.cast (ref $type33)
          (local.get $5)
         )
        )
        (i32.const 0)
       )
       (else
        (i32.const 1)
       )
      )
      (then
       (call $function55
        (local.get $0)
        (i32.const 0)
        (i32.const 1)
        (local.get $1)
       )
      )
      (else
       (if
        (i32.eqz
         (global.get $ready139)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global139)
        )
       )
       (if
        (i32.eqz
         (ref.test (ref $type38)
          (local.get $1)
         )
        )
        (then
         (unreachable)
        )
       )
       (call $function62
        (local.get $4)
        (i32.const 0)
        (i32.const 1)
        (local.tee $6
         (ref.cast (ref $type38)
          (local.get $1)
         )
        )
        (struct.get $type39 0
         (struct.get $type38 1
          (local.get $6)
         )
        )
       )
      )
     )
    )
    (if
     (i32.eqz
      (local.get $3)
     )
     (then
      (unreachable)
     )
    )
    (return_call $function54
     (local.get $0)
     (local.get $1)
     (local.get $2)
     (local.get $3)
     (i64.sub
      (local.get $4)
      (i64.const 1)
     )
    )
   )
  )
 )
 (func $function55 (type $13) (param $0 i64) (param $1 i32) (param $2 i32) (param $3 (ref $type36)) (result i32)
  (local $4 (ref $type33))
  (local $5 (ref $type33))
  (local $6 (ref $type28))
  (local $7 (ref $type31))
  (local $8 (ref $type31))
  (local $9 (ref $type32))
  (local $10 i64)
  (local $scratch (ref $type28))
  (local $scratch_12 (ref $type28))
  (local $scratch_13 (ref $type28))
  (local $scratch_14 (ref $type28))
  (local $scratch_15 (ref $type28))
  (local $scratch_16 (ref $type28))
  (local $scratch_17 (ref $type28))
  (local $scratch_18 (ref $type28))
  (local $scratch_19 (ref $type28))
  (local $scratch_20 (ref $type28))
  (local $scratch_21 (ref $type28))
  (local $scratch_22 (ref $type28))
  (local $scratch_23 (ref $type28))
  (local $scratch_24 (ref $type28))
  (if
   (i32.eqz
    (global.get $ready132)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global132)
   )
  )
  (if (result i32)
   (if (result i32)
    (ref.test (ref $type38)
     (local.get $3)
    )
    (then
     (drop
      (ref.cast (ref $type38)
       (local.get $3)
      )
     )
     (i32.const 0)
    )
    (else
     (i32.const 1)
    )
   )
   (then
    (i32.const 0)
   )
   (else
    (if
     (i32.eqz
      (global.get $ready137)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global137)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type38)
       (local.get $3)
      )
     )
     (then
      (unreachable)
     )
    )
    (local.set $7
     (struct.get $type35 0
      (struct.get $type38 0
       (ref.cast (ref $type38)
        (local.get $3)
       )
      )
     )
    )
    (if
     (i32.eqz
      (global.get $ready120)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global120)
     )
    )
    (if
     (if (result i32)
      (ref.test (ref $type33)
       (local.get $7)
      )
      (then
       (drop
        (ref.cast (ref $type33)
         (local.get $7)
        )
       )
       (i32.const 0)
      )
      (else
       (i32.const 1)
      )
     )
     (then
      (if
       (i32.eqz
        (global.get $ready109)
       )
       (then
        (unreachable)
       )
      )
      (local.set $6
       (ref.as_non_null
        (global.get $global109)
       )
      )
      (if
       (i32.eqz
        (global.get $ready155)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global155)
       )
      )
      (if
       (i32.eqz
        (global.get $ready158)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global158)
       )
      )
      (if
       (i32.eqz
        (ref.test (ref $type38)
         (local.get $3)
        )
       )
       (then
        (unreachable)
       )
      )
      (struct.set $type35 0
       (struct.get $type38 0
        (ref.cast (ref $type38)
         (local.get $3)
        )
       )
       (struct.new $type33
        (struct.new $type34
         (local.get $6)
        )
        (struct.new $type35
         (struct.new_default $type32)
        )
       )
      )
     )
    )
    (if
     (i32.eqz
      (global.get $ready137)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global137)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type38)
       (local.get $3)
      )
     )
     (then
      (unreachable)
     )
    )
    (local.set $8
     (struct.get $type35 0
      (struct.get $type38 0
       (ref.cast (ref $type38)
        (local.get $3)
       )
      )
     )
    )
    (local.set $9
     (struct.new_default $type32)
    )
    (local.set $7
     (if (result (ref $type31))
      (i64.eqz
       (local.get $0)
      )
      (then
       (local.get $9)
      )
      (else
       (if
        (i32.eqz
         (global.get $ready109)
        )
        (then
         (unreachable)
        )
       )
       (local.set $4
        (struct.new $type33
         (struct.new $type34
          (block (result (ref $type28))
           (local.set $scratch
            (ref.as_non_null
             (global.get $global109)
            )
           )
           (if
            (i32.eqz
             (global.get $ready155)
            )
            (then
             (unreachable)
            )
           )
           (drop
            (ref.as_non_null
             (global.get $global155)
            )
           )
           (local.get $scratch)
          )
         )
         (struct.new $type35
          (local.get $9)
         )
        )
       )
       (if (result (ref $type31))
        (i64.eqz
         (local.tee $10
          (i64.sub
           (local.get $0)
           (i64.const 1)
          )
         )
        )
        (then
         (local.get $4)
        )
        (else
         (if
          (i32.eqz
           (global.get $ready109)
          )
          (then
           (unreachable)
          )
         )
         (local.set $4
          (struct.new $type33
           (struct.new $type34
            (block (result (ref $type28))
             (local.set $scratch_12
              (ref.as_non_null
               (global.get $global109)
              )
             )
             (if
              (i32.eqz
               (global.get $ready155)
              )
              (then
               (unreachable)
              )
             )
             (drop
              (ref.as_non_null
               (global.get $global155)
              )
             )
             (local.get $scratch_12)
            )
           )
           (struct.new $type35
            (local.get $4)
           )
          )
         )
         (if (result (ref $type31))
          (i64.eqz
           (local.tee $10
            (i64.sub
             (local.get $10)
             (i64.const 1)
            )
           )
          )
          (then
           (local.get $4)
          )
          (else
           (if
            (i32.eqz
             (global.get $ready109)
            )
            (then
             (unreachable)
            )
           )
           (local.set $4
            (struct.new $type33
             (struct.new $type34
              (block (result (ref $type28))
               (local.set $scratch_13
                (ref.as_non_null
                 (global.get $global109)
                )
               )
               (if
                (i32.eqz
                 (global.get $ready155)
                )
                (then
                 (unreachable)
                )
               )
               (drop
                (ref.as_non_null
                 (global.get $global155)
                )
               )
               (local.get $scratch_13)
              )
             )
             (struct.new $type35
              (local.get $4)
             )
            )
           )
           (if (result (ref $type31))
            (i64.eqz
             (local.tee $10
              (i64.sub
               (local.get $10)
               (i64.const 1)
              )
             )
            )
            (then
             (local.get $4)
            )
            (else
             (if
              (i32.eqz
               (global.get $ready109)
              )
              (then
               (unreachable)
              )
             )
             (local.set $4
              (struct.new $type33
               (struct.new $type34
                (block (result (ref $type28))
                 (local.set $scratch_14
                  (ref.as_non_null
                   (global.get $global109)
                  )
                 )
                 (if
                  (i32.eqz
                   (global.get $ready155)
                  )
                  (then
                   (unreachable)
                  )
                 )
                 (drop
                  (ref.as_non_null
                   (global.get $global155)
                  )
                 )
                 (local.get $scratch_14)
                )
               )
               (struct.new $type35
                (local.get $4)
               )
              )
             )
             (if (result (ref $type31))
              (i64.eqz
               (local.tee $10
                (i64.sub
                 (local.get $10)
                 (i64.const 1)
                )
               )
              )
              (then
               (local.get $4)
              )
              (else
               (if
                (i32.eqz
                 (global.get $ready109)
                )
                (then
                 (unreachable)
                )
               )
               (local.set $4
                (struct.new $type33
                 (struct.new $type34
                  (block (result (ref $type28))
                   (local.set $scratch_15
                    (ref.as_non_null
                     (global.get $global109)
                    )
                   )
                   (if
                    (i32.eqz
                     (global.get $ready155)
                    )
                    (then
                     (unreachable)
                    )
                   )
                   (drop
                    (ref.as_non_null
                     (global.get $global155)
                    )
                   )
                   (local.get $scratch_15)
                  )
                 )
                 (struct.new $type35
                  (local.get $4)
                 )
                )
               )
               (if (result (ref $type31))
                (i64.eqz
                 (local.tee $10
                  (i64.sub
                   (local.get $10)
                   (i64.const 1)
                  )
                 )
                )
                (then
                 (local.get $4)
                )
                (else
                 (if
                  (i32.eqz
                   (global.get $ready109)
                  )
                  (then
                   (unreachable)
                  )
                 )
                 (local.set $4
                  (struct.new $type33
                   (struct.new $type34
                    (block (result (ref $type28))
                     (local.set $scratch_16
                      (ref.as_non_null
                       (global.get $global109)
                      )
                     )
                     (if
                      (i32.eqz
                       (global.get $ready155)
                      )
                      (then
                       (unreachable)
                      )
                     )
                     (drop
                      (ref.as_non_null
                       (global.get $global155)
                      )
                     )
                     (local.get $scratch_16)
                    )
                   )
                   (struct.new $type35
                    (local.get $4)
                   )
                  )
                 )
                 (if (result (ref $type31))
                  (i64.eqz
                   (local.tee $10
                    (i64.sub
                     (local.get $10)
                     (i64.const 1)
                    )
                   )
                  )
                  (then
                   (local.get $4)
                  )
                  (else
                   (if
                    (i32.eqz
                     (global.get $ready109)
                    )
                    (then
                     (unreachable)
                    )
                   )
                   (local.set $4
                    (struct.new $type33
                     (struct.new $type34
                      (block (result (ref $type28))
                       (local.set $scratch_17
                        (ref.as_non_null
                         (global.get $global109)
                        )
                       )
                       (if
                        (i32.eqz
                         (global.get $ready155)
                        )
                        (then
                         (unreachable)
                        )
                       )
                       (drop
                        (ref.as_non_null
                         (global.get $global155)
                        )
                       )
                       (local.get $scratch_17)
                      )
                     )
                     (struct.new $type35
                      (local.get $4)
                     )
                    )
                   )
                   (if (result (ref $type31))
                    (i64.eqz
                     (local.tee $10
                      (i64.sub
                       (local.get $10)
                       (i64.const 1)
                      )
                     )
                    )
                    (then
                     (local.get $4)
                    )
                    (else
                     (if
                      (i32.eqz
                       (global.get $ready109)
                      )
                      (then
                       (unreachable)
                      )
                     )
                     (local.set $4
                      (struct.new $type33
                       (struct.new $type34
                        (block (result (ref $type28))
                         (local.set $scratch_18
                          (ref.as_non_null
                           (global.get $global109)
                          )
                         )
                         (if
                          (i32.eqz
                           (global.get $ready155)
                          )
                          (then
                           (unreachable)
                          )
                         )
                         (drop
                          (ref.as_non_null
                           (global.get $global155)
                          )
                         )
                         (local.get $scratch_18)
                        )
                       )
                       (struct.new $type35
                        (local.get $4)
                       )
                      )
                     )
                     (if (result (ref $type31))
                      (i64.eqz
                       (local.tee $10
                        (i64.sub
                         (local.get $10)
                         (i64.const 1)
                        )
                       )
                      )
                      (then
                       (local.get $4)
                      )
                      (else
                       (if
                        (i32.eqz
                         (global.get $ready109)
                        )
                        (then
                         (unreachable)
                        )
                       )
                       (local.set $4
                        (struct.new $type33
                         (struct.new $type34
                          (block (result (ref $type28))
                           (local.set $scratch_19
                            (ref.as_non_null
                             (global.get $global109)
                            )
                           )
                           (if
                            (i32.eqz
                             (global.get $ready155)
                            )
                            (then
                             (unreachable)
                            )
                           )
                           (drop
                            (ref.as_non_null
                             (global.get $global155)
                            )
                           )
                           (local.get $scratch_19)
                          )
                         )
                         (struct.new $type35
                          (local.get $4)
                         )
                        )
                       )
                       (if (result (ref $type31))
                        (i64.eqz
                         (local.tee $10
                          (i64.sub
                           (local.get $10)
                           (i64.const 1)
                          )
                         )
                        )
                        (then
                         (local.get $4)
                        )
                        (else
                         (if
                          (i32.eqz
                           (global.get $ready109)
                          )
                          (then
                           (unreachable)
                          )
                         )
                         (local.set $4
                          (struct.new $type33
                           (struct.new $type34
                            (block (result (ref $type28))
                             (local.set $scratch_20
                              (ref.as_non_null
                               (global.get $global109)
                              )
                             )
                             (if
                              (i32.eqz
                               (global.get $ready155)
                              )
                              (then
                               (unreachable)
                              )
                             )
                             (drop
                              (ref.as_non_null
                               (global.get $global155)
                              )
                             )
                             (local.get $scratch_20)
                            )
                           )
                           (struct.new $type35
                            (local.get $4)
                           )
                          )
                         )
                         (if (result (ref $type31))
                          (i64.eqz
                           (local.tee $10
                            (i64.sub
                             (local.get $10)
                             (i64.const 1)
                            )
                           )
                          )
                          (then
                           (local.get $4)
                          )
                          (else
                           (if
                            (i32.eqz
                             (global.get $ready109)
                            )
                            (then
                             (unreachable)
                            )
                           )
                           (local.set $4
                            (struct.new $type33
                             (struct.new $type34
                              (block (result (ref $type28))
                               (local.set $scratch_21
                                (ref.as_non_null
                                 (global.get $global109)
                                )
                               )
                               (if
                                (i32.eqz
                                 (global.get $ready155)
                                )
                                (then
                                 (unreachable)
                                )
                               )
                               (drop
                                (ref.as_non_null
                                 (global.get $global155)
                                )
                               )
                               (local.get $scratch_21)
                              )
                             )
                             (struct.new $type35
                              (local.get $4)
                             )
                            )
                           )
                           (if (result (ref $type31))
                            (i64.eqz
                             (local.tee $10
                              (i64.sub
                               (local.get $10)
                               (i64.const 1)
                              )
                             )
                            )
                            (then
                             (local.get $4)
                            )
                            (else
                             (if
                              (i32.eqz
                               (global.get $ready109)
                              )
                              (then
                               (unreachable)
                              )
                             )
                             (local.set $4
                              (struct.new $type33
                               (struct.new $type34
                                (block (result (ref $type28))
                                 (local.set $scratch_22
                                  (ref.as_non_null
                                   (global.get $global109)
                                  )
                                 )
                                 (if
                                  (i32.eqz
                                   (global.get $ready155)
                                  )
                                  (then
                                   (unreachable)
                                  )
                                 )
                                 (drop
                                  (ref.as_non_null
                                   (global.get $global155)
                                  )
                                 )
                                 (local.get $scratch_22)
                                )
                               )
                               (struct.new $type35
                                (local.get $4)
                               )
                              )
                             )
                             (if (result (ref $type31))
                              (i64.eqz
                               (local.tee $10
                                (i64.sub
                                 (local.get $10)
                                 (i64.const 1)
                                )
                               )
                              )
                              (then
                               (local.get $4)
                              )
                              (else
                               (if
                                (i32.eqz
                                 (global.get $ready109)
                                )
                                (then
                                 (unreachable)
                                )
                               )
                               (local.set $4
                                (struct.new $type33
                                 (struct.new $type34
                                  (block (result (ref $type28))
                                   (local.set $scratch_23
                                    (ref.as_non_null
                                     (global.get $global109)
                                    )
                                   )
                                   (if
                                    (i32.eqz
                                     (global.get $ready155)
                                    )
                                    (then
                                     (unreachable)
                                    )
                                   )
                                   (drop
                                    (ref.as_non_null
                                     (global.get $global155)
                                    )
                                   )
                                   (local.get $scratch_23)
                                  )
                                 )
                                 (struct.new $type35
                                  (local.get $4)
                                 )
                                )
                               )
                               (if (result (ref $type31))
                                (i64.eqz
                                 (local.tee $10
                                  (i64.sub
                                   (local.get $10)
                                   (i64.const 1)
                                  )
                                 )
                                )
                                (then
                                 (local.get $4)
                                )
                                (else
                                 (if
                                  (i32.eqz
                                   (global.get $ready109)
                                  )
                                  (then
                                   (unreachable)
                                  )
                                 )
                                 (local.set $4
                                  (struct.new $type33
                                   (struct.new $type34
                                    (block (result (ref $type28))
                                     (local.set $scratch_24
                                      (ref.as_non_null
                                       (global.get $global109)
                                      )
                                     )
                                     (if
                                      (i32.eqz
                                       (global.get $ready155)
                                      )
                                      (then
                                       (unreachable)
                                      )
                                     )
                                     (drop
                                      (ref.as_non_null
                                       (global.get $global155)
                                      )
                                     )
                                     (local.get $scratch_24)
                                    )
                                   )
                                   (struct.new $type35
                                    (local.get $4)
                                   )
                                  )
                                 )
                                 (if (result (ref $type31))
                                  (i64.eqz
                                   (local.tee $10
                                    (i64.sub
                                     (local.get $10)
                                     (i64.const 1)
                                    )
                                   )
                                  )
                                  (then
                                   (local.get $4)
                                  )
                                  (else
                                   (if
                                    (i32.eqz
                                     (global.get $ready109)
                                    )
                                    (then
                                     (unreachable)
                                    )
                                   )
                                   (local.set $6
                                    (ref.as_non_null
                                     (global.get $global109)
                                    )
                                   )
                                   (if
                                    (i32.eqz
                                     (global.get $ready155)
                                    )
                                    (then
                                     (unreachable)
                                    )
                                   )
                                   (drop
                                    (ref.as_non_null
                                     (global.get $global155)
                                    )
                                   )
                                   (call $function58
                                    (i32.const 0)
                                    (i32.const 1)
                                    (i64.sub
                                     (local.get $10)
                                     (i64.const 1)
                                    )
                                    (call $function56
                                     (local.get $6)
                                     (local.get $4)
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
    (if
     (i32.eqz
      (global.get $ready164)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global164)
     )
    )
    (if
     (i32.eqz
      (global.get $ready120)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global120)
     )
    )
    (drop
     (if (result (ref $type31))
      (if (result i32)
       (ref.test (ref $type33)
        (local.get $8)
       )
       (then
        (drop
         (ref.cast (ref $type33)
          (local.get $8)
         )
        )
        (i32.const 0)
       )
       (else
        (i32.const 1)
       )
      )
      (then
       (local.get $7)
      )
      (else
       (if
        (i32.eqz
         (global.get $ready127)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global127)
        )
       )
       (if
        (i32.eqz
         (ref.test (ref $type33)
          (local.get $8)
         )
        )
        (then
         (unreachable)
        )
       )
       (call $function60
        (local.tee $5
         (ref.cast (ref $type33)
          (local.get $8)
         )
        )
        (local.get $7)
        (i32.const 0)
        (i32.const 1)
        (local.get $5)
        (struct.get $type35 0
         (struct.get $type33 1
          (local.get $5)
         )
        )
       )
      )
     )
    )
    (if
     (i32.eqz
      (global.get $ready139)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global139)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type38)
       (local.get $3)
      )
     )
     (then
      (unreachable)
     )
    )
    (local.set $3
     (struct.get $type39 0
      (struct.get $type38 1
       (ref.cast (ref $type38)
        (local.get $3)
       )
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
    (return_call $function55
     (local.get $0)
     (local.get $1)
     (local.get $2)
     (local.get $3)
    )
   )
  )
 )
 (func $function56 (type $12) (param $0 (ref $type28)) (param $1 (ref $type33)) (result (ref $type33))
  (struct.new $type33
   (struct.new $type34
    (local.get $0)
   )
   (struct.new $type35
    (local.get $1)
   )
  )
 )
 (func $function58 (type $11) (param $0 i32) (param $1 i32) (param $2 i64) (param $3 (ref $type33)) (result (ref $type31))
  (local $4 (ref $type28))
  (if (result (ref $type33))
   (i64.eqz
    (local.get $2)
   )
   (then
    (local.get $3)
   )
   (else
    (if
     (i32.eqz
      (global.get $ready109)
     )
     (then
      (unreachable)
     )
    )
    (local.set $3
     (call $function56
      (ref.as_non_null
       (global.get $global109)
      )
      (block (result (ref $type33))
       (if
        (i32.eqz
         (global.get $ready155)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global155)
        )
       )
       (local.get $3)
      )
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
    (return_call $function58
     (local.get $0)
     (local.get $1)
     (i64.sub
      (local.get $2)
      (i64.const 1)
     )
     (local.get $3)
    )
   )
  )
 )
 (func $function60 (type $10) (param $0 (ref $type31)) (param $1 (ref $type31)) (param $2 i32) (param $3 i32) (param $4 (ref $type31)) (param $5 (ref $type31)) (result (ref $type31))
  (if
   (i32.eqz
    (global.get $ready120)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global120)
   )
  )
  (if (result (ref $type31))
   (if (result i32)
    (ref.test (ref $type33)
     (local.get $5)
    )
    (then
     (drop
      (ref.cast (ref $type33)
       (local.get $5)
      )
     )
     (i32.const 0)
    )
    (else
     (i32.const 1)
    )
   )
   (then
    (if
     (i32.eqz
      (global.get $ready170)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global170)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type33)
       (local.get $4)
      )
     )
     (then
      (unreachable)
     )
    )
    (struct.set $type35 0
     (struct.get $type33 1
      (ref.cast (ref $type33)
       (local.get $4)
      )
     )
     (local.get $1)
    )
    (local.get $0)
   )
   (else
    (if
     (i32.eqz
      (global.get $ready127)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global127)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type33)
       (local.get $5)
      )
     )
     (then
      (unreachable)
     )
    )
    (local.set $4
     (struct.get $type35 0
      (struct.get $type33 1
       (ref.cast (ref $type33)
        (local.get $5)
       )
      )
     )
    )
    (if
     (i32.eqz
      (local.get $3)
     )
     (then
      (unreachable)
     )
    )
    (return_call $function60
     (local.get $0)
     (local.get $1)
     (local.get $2)
     (local.get $3)
     (local.get $5)
     (local.get $4)
    )
   )
  )
 )
 (func $function62 (type $9) (param $0 i64) (param $1 i32) (param $2 i32) (param $3 (ref $type36)) (param $4 (ref $type36)) (result i32)
  (local $5 (ref $type31))
  (local $6 (ref $type31))
  (local $7 i64)
  (if
   (i32.eqz
    (global.get $ready132)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global132)
   )
  )
  (if (result i32)
   (if (result i32)
    (ref.test (ref $type38)
     (local.get $4)
    )
    (then
     (drop
      (ref.cast (ref $type38)
       (local.get $4)
      )
     )
     (i32.const 0)
    )
    (else
     (i32.const 1)
    )
   )
   (then
    (i32.const 0)
   )
   (else
    (if
     (i32.eqz
      (global.get $ready137)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global137)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type38)
       (local.get $3)
      )
     )
     (then
      (unreachable)
     )
    )
    (local.set $5
     (struct.get $type35 0
      (struct.get $type38 0
       (ref.cast (ref $type38)
        (local.get $3)
       )
      )
     )
    )
    (if
     (i32.eqz
      (global.get $ready178)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global178)
     )
    )
    (local.set $6
     (if (result (ref $type31))
      (i64.eqz
       (local.tee $7
        (i64.div_s
         (call $function64
          (i32.const 0)
          (i32.const 1)
          (local.get $5)
          (i64.const 0)
         )
         (i64.const 2)
        )
       )
      )
      (then
       (if
        (i32.eqz
         (global.get $ready158)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global158)
        )
       )
       (if
        (i32.eqz
         (ref.test (ref $type38)
          (local.get $3)
         )
        )
        (then
         (unreachable)
        )
       )
       (struct.set $type35 0
        (struct.get $type38 0
         (ref.cast (ref $type38)
          (local.get $3)
         )
        )
        (struct.new_default $type32)
       )
       (if
        (i32.eqz
         (global.get $ready137)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global137)
        )
       )
       (if
        (i32.eqz
         (ref.test (ref $type38)
          (local.get $3)
         )
        )
        (then
         (unreachable)
        )
       )
       (struct.get $type35 0
        (struct.get $type38 0
         (ref.cast (ref $type38)
          (local.get $3)
         )
        )
       )
      )
      (else
       (if
        (i32.eqz
         (global.get $ready137)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global137)
        )
       )
       (if
        (i32.eqz
         (ref.test (ref $type38)
          (local.get $3)
         )
        )
        (then
         (unreachable)
        )
       )
       (call $function65
        (local.get $0)
        (i32.const 0)
        (i32.const 1)
        (local.get $7)
        (struct.get $type35 0
         (struct.get $type38 0
          (ref.cast (ref $type38)
           (local.get $3)
          )
         )
        )
       )
      )
     )
    )
    (if
     (i32.eqz
      (global.get $ready137)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global137)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type38)
       (local.get $4)
      )
     )
     (then
      (unreachable)
     )
    )
    (local.set $5
     (struct.get $type35 0
      (struct.get $type38 0
       (ref.cast (ref $type38)
        (local.get $4)
       )
      )
     )
    )
    (if
     (i32.eqz
      (global.get $ready178)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global178)
     )
    )
    (local.set $7
     (call $function64
      (i32.const 0)
      (i32.const 1)
      (local.get $5)
      (i64.const 0)
     )
    )
    (if
     (i32.eqz
      (global.get $ready137)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global137)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type38)
       (local.get $4)
      )
     )
     (then
      (unreachable)
     )
    )
    (local.set $5
     (call $function67
      (local.get $0)
      (i32.const 0)
      (i32.const 1)
      (i64.div_s
       (local.get $7)
       (i64.const 2)
      )
      (struct.get $type35 0
       (struct.get $type38 0
        (ref.cast (ref $type38)
         (local.get $4)
        )
       )
      )
     )
    )
    (if
     (i32.eqz
      (global.get $ready170)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global170)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type33)
       (local.get $5)
      )
     )
     (then
      (unreachable)
     )
    )
    (struct.set $type35 0
     (struct.get $type33 1
      (ref.cast (ref $type33)
       (local.get $5)
      )
     )
     (local.get $6)
    )
    (if
     (i32.eqz
      (global.get $ready139)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global139)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type38)
       (local.get $3)
      )
     )
     (then
      (unreachable)
     )
    )
    (local.set $3
     (struct.get $type39 0
      (struct.get $type38 1
       (ref.cast (ref $type38)
        (local.get $3)
       )
      )
     )
    )
    (if
     (i32.eqz
      (global.get $ready139)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global139)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type38)
       (local.get $4)
      )
     )
     (then
      (unreachable)
     )
    )
    (local.set $4
     (struct.get $type39 0
      (struct.get $type38 1
       (ref.cast (ref $type38)
        (local.get $4)
       )
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
    (return_call $function62
     (local.get $0)
     (local.get $1)
     (local.get $2)
     (local.get $3)
     (local.get $4)
    )
   )
  )
 )
 (func $function64 (type $8) (param $0 i32) (param $1 i32) (param $2 (ref $type31)) (param $3 i64) (result i64)
  (if
   (i32.eqz
    (global.get $ready120)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global120)
   )
  )
  (if (result i64)
   (if (result i32)
    (ref.test (ref $type33)
     (local.get $2)
    )
    (then
     (drop
      (ref.cast (ref $type33)
       (local.get $2)
      )
     )
     (i32.const 0)
    )
    (else
     (i32.const 1)
    )
   )
   (then
    (local.get $3)
   )
   (else
    (if
     (i32.eqz
      (global.get $ready127)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global127)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type33)
       (local.get $2)
      )
     )
     (then
      (unreachable)
     )
    )
    (local.set $2
     (struct.get $type35 0
      (struct.get $type33 1
       (ref.cast (ref $type33)
        (local.get $2)
       )
      )
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
    (return_call $function64
     (local.get $0)
     (local.get $1)
     (local.get $2)
     (i64.add
      (local.get $3)
      (i64.const 1)
     )
    )
   )
  )
 )
 (func $function65 (type $7) (param $0 i64) (param $1 i32) (param $2 i32) (param $3 i64) (param $4 (ref $type31)) (result (ref $type31))
  (local $5 (ref $type31))
  (local $scratch (ref $type31))
  (if (result (ref $type31))
   (i64.eq
    (local.get $3)
    (i64.const 1)
   )
   (then
    (if
     (i32.eqz
      (global.get $ready127)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global127)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type33)
       (local.get $4)
      )
     )
     (then
      (unreachable)
     )
    )
    (local.set $scratch
     (struct.get $type35 0
      (struct.get $type33 1
       (ref.cast (ref $type33)
        (local.get $4)
       )
      )
     )
    )
    (if
     (i32.eqz
      (global.get $ready170)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global170)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type33)
       (local.get $4)
      )
     )
     (then
      (unreachable)
     )
    )
    (struct.set $type35 0
     (struct.get $type33 1
      (ref.cast (ref $type33)
       (local.get $4)
      )
     )
     (struct.new_default $type32)
    )
    (local.get $scratch)
   )
   (else
    (if
     (i32.eqz
      (global.get $ready187)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global187)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type33)
       (local.get $4)
      )
     )
     (then
      (unreachable)
     )
    )
    (struct.set $type34 0
     (struct.get $type33 0
      (ref.cast (ref $type33)
       (local.get $4)
      )
     )
     (struct.new $type29
      (local.get $0)
     )
    )
    (if
     (i32.eqz
      (global.get $ready127)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global127)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type33)
       (local.get $4)
      )
     )
     (then
      (unreachable)
     )
    )
    (local.set $4
     (struct.get $type35 0
      (struct.get $type33 1
       (ref.cast (ref $type33)
        (local.get $4)
       )
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
    (return_call $function65
     (local.get $0)
     (local.get $1)
     (local.get $2)
     (i64.sub
      (local.get $3)
      (i64.const 1)
     )
     (local.get $4)
    )
   )
  )
 )
 (func $function67 (type $7) (param $0 i64) (param $1 i32) (param $2 i32) (param $3 i64) (param $4 (ref $type31)) (result (ref $type31))
  (if
   (i32.eqz
    (global.get $ready194)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global194)
   )
  )
  (if (result (ref $type31))
   (i64.eqz
    (local.get $3)
   )
   (then
    (local.get $4)
   )
   (else
    (if
     (i32.eqz
      (global.get $ready187)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global187)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type33)
       (local.get $4)
      )
     )
     (then
      (unreachable)
     )
    )
    (struct.set $type34 0
     (struct.get $type33 0
      (ref.cast (ref $type33)
       (local.get $4)
      )
     )
     (struct.new $type29
      (local.get $0)
     )
    )
    (if
     (i32.eqz
      (global.get $ready127)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global127)
     )
    )
    (if
     (i32.eqz
      (ref.test (ref $type33)
       (local.get $4)
      )
     )
     (then
      (unreachable)
     )
    )
    (local.set $4
     (struct.get $type35 0
      (struct.get $type33 1
       (ref.cast (ref $type33)
        (local.get $4)
       )
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
    (return_call $function67
     (local.get $0)
     (local.get $1)
     (local.get $2)
     (i64.sub
      (local.get $3)
      (i64.const 1)
     )
     (local.get $4)
    )
   )
  )
 )
 (func $function70 (type $call62) (result (ref $type27))
  (local $0 i64)
  (local $1 (ref $type61))
  (local $scratch i64)
  (local $scratch_3 i64)
  (if
   (i32.eqz
    (global.get $ready197)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global197)
   )
  )
  (if
   (i32.eqz
    (global.get $ready196)
   )
   (then
    (unreachable)
   )
  )
  (if (result (ref $type27))
   (i64.eqz
    (block (result i64)
     (local.set $scratch
      (call $foreign0
       (struct.get $type61 0
        (global.get $global196)
       )
      )
     )
     (if
      (i32.eqz
       (global.get $ready196)
      )
      (then
       (unreachable)
      )
     )
     (struct.set $type61 0
      (ref.as_non_null
       (global.get $global196)
      )
      (block (result i64)
       (if
        (i32.eqz
         (global.get $ready196)
        )
        (then
         (unreachable)
        )
       )
       (i64.add
        (struct.get $type61 0
         (global.get $global196)
        )
        (i64.const 1)
       )
      )
     )
     (local.get $scratch)
    )
   )
   (then
    (if
     (i32.eqz
      (global.get $ready109)
     )
     (then
      (unreachable)
     )
    )
    (ref.as_non_null
     (global.get $global109)
    )
   )
   (else
    (if
     (i32.eqz
      (global.get $ready197)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global197)
     )
    )
    (if
     (i32.eqz
      (global.get $ready196)
     )
     (then
      (unreachable)
     )
    )
    (struct.new $type29
     (block (result i64)
      (local.set $scratch_3
       (call $foreign0
        (struct.get $type61 0
         (global.get $global196)
        )
       )
      )
      (if
       (i32.eqz
        (global.get $ready196)
       )
       (then
        (unreachable)
       )
      )
      (struct.set $type61 0
       (ref.as_non_null
        (global.get $global196)
       )
       (block (result i64)
        (if
         (i32.eqz
          (global.get $ready196)
         )
         (then
          (unreachable)
         )
        )
        (i64.add
         (struct.get $type61 0
          (global.get $global196)
         )
         (i64.const 1)
        )
       )
      )
      (local.get $scratch_3)
     )
    )
   )
  )
 )
 (func $function71 (type $call64) (param $0 i64) (result (ref null $type57))
  (local $1 i64)
  (local $2 (ref $type27))
  (local $3 (ref $type61))
  (local $4 (ref null $type55))
  (if (result (ref null $type57))
   (i64.eqz
    (local.get $0)
   )
   (then
    (ref.null none)
   )
   (else
    (if
     (i32.eqz
      (global.get $ready197)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global197)
     )
    )
    (if
     (i32.eqz
      (global.get $ready196)
     )
     (then
      (unreachable)
     )
    )
    (local.set $1
     (call $foreign0
      (struct.get $type61 0
       (global.get $global196)
      )
     )
    )
    (if
     (i32.eqz
      (global.get $ready196)
     )
     (then
      (unreachable)
     )
    )
    (struct.set $type61 0
     (ref.as_non_null
      (global.get $global196)
     )
     (block (result i64)
      (if
       (i32.eqz
        (global.get $ready196)
       )
       (then
        (unreachable)
       )
      )
      (i64.add
       (struct.get $type61 0
        (global.get $global196)
       )
       (i64.const 1)
      )
     )
    )
    (if
     (i32.eqz
      (global.get $ready207)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global207)
     )
    )
    (struct.new $type57
     (if (result (ref null $type55))
      (i64.eqz
       (local.get $1)
      )
      (then
       (ref.null none)
      )
      (else
       (if
        (i32.eqz
         (global.get $ready199)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global199)
        )
       )
       (struct.new $type55
        (call $function70)
        (block (result (ref null $type55))
         (if
          (i32.eqz
           (global.get $ready207)
          )
          (then
           (unreachable)
          )
         )
         (drop
          (ref.as_non_null
           (global.get $global207)
          )
         )
         (if (result (ref null $type55))
          (i64.eqz
           (local.tee $1
            (i64.sub
             (local.get $1)
             (i64.const 1)
            )
           )
          )
          (then
           (ref.null none)
          )
          (else
           (if
            (i32.eqz
             (global.get $ready199)
            )
            (then
             (unreachable)
            )
           )
           (drop
            (ref.as_non_null
             (global.get $global199)
            )
           )
           (struct.new $type55
            (call $function70)
            (block (result (ref null $type55))
             (if
              (i32.eqz
               (global.get $ready207)
              )
              (then
               (unreachable)
              )
             )
             (drop
              (ref.as_non_null
               (global.get $global207)
              )
             )
             (if (result (ref null $type55))
              (i64.eqz
               (local.tee $1
                (i64.sub
                 (local.get $1)
                 (i64.const 1)
                )
               )
              )
              (then
               (ref.null none)
              )
              (else
               (if
                (i32.eqz
                 (global.get $ready199)
                )
                (then
                 (unreachable)
                )
               )
               (drop
                (ref.as_non_null
                 (global.get $global199)
                )
               )
               (struct.new $type55
                (call $function70)
                (block (result (ref null $type55))
                 (if
                  (i32.eqz
                   (global.get $ready207)
                  )
                  (then
                   (unreachable)
                  )
                 )
                 (drop
                  (ref.as_non_null
                   (global.get $global207)
                  )
                 )
                 (if (result (ref null $type55))
                  (i64.eqz
                   (local.tee $1
                    (i64.sub
                     (local.get $1)
                     (i64.const 1)
                    )
                   )
                  )
                  (then
                   (ref.null none)
                  )
                  (else
                   (if
                    (i32.eqz
                     (global.get $ready199)
                    )
                    (then
                     (unreachable)
                    )
                   )
                   (drop
                    (ref.as_non_null
                     (global.get $global199)
                    )
                   )
                   (struct.new $type55
                    (call $function70)
                    (block (result (ref null $type55))
                     (if
                      (i32.eqz
                       (global.get $ready207)
                      )
                      (then
                       (unreachable)
                      )
                     )
                     (drop
                      (ref.as_non_null
                       (global.get $global207)
                      )
                     )
                     (if (result (ref null $type55))
                      (i64.eqz
                       (local.tee $1
                        (i64.sub
                         (local.get $1)
                         (i64.const 1)
                        )
                       )
                      )
                      (then
                       (ref.null none)
                      )
                      (else
                       (if
                        (i32.eqz
                         (global.get $ready199)
                        )
                        (then
                         (unreachable)
                        )
                       )
                       (drop
                        (ref.as_non_null
                         (global.get $global199)
                        )
                       )
                       (struct.new $type55
                        (call $function70)
                        (block (result (ref null $type55))
                         (if
                          (i32.eqz
                           (global.get $ready207)
                          )
                          (then
                           (unreachable)
                          )
                         )
                         (drop
                          (ref.as_non_null
                           (global.get $global207)
                          )
                         )
                         (if (result (ref null $type55))
                          (i64.eqz
                           (local.tee $1
                            (i64.sub
                             (local.get $1)
                             (i64.const 1)
                            )
                           )
                          )
                          (then
                           (ref.null none)
                          )
                          (else
                           (if
                            (i32.eqz
                             (global.get $ready199)
                            )
                            (then
                             (unreachable)
                            )
                           )
                           (drop
                            (ref.as_non_null
                             (global.get $global199)
                            )
                           )
                           (struct.new $type55
                            (call $function70)
                            (block (result (ref null $type55))
                             (if
                              (i32.eqz
                               (global.get $ready207)
                              )
                              (then
                               (unreachable)
                              )
                             )
                             (drop
                              (ref.as_non_null
                               (global.get $global207)
                              )
                             )
                             (if (result (ref null $type55))
                              (i64.eqz
                               (local.tee $1
                                (i64.sub
                                 (local.get $1)
                                 (i64.const 1)
                                )
                               )
                              )
                              (then
                               (ref.null none)
                              )
                              (else
                               (if
                                (i32.eqz
                                 (global.get $ready199)
                                )
                                (then
                                 (unreachable)
                                )
                               )
                               (drop
                                (ref.as_non_null
                                 (global.get $global199)
                                )
                               )
                               (struct.new $type55
                                (call $function70)
                                (block (result (ref null $type55))
                                 (if
                                  (i32.eqz
                                   (global.get $ready207)
                                  )
                                  (then
                                   (unreachable)
                                  )
                                 )
                                 (drop
                                  (ref.as_non_null
                                   (global.get $global207)
                                  )
                                 )
                                 (if (result (ref null $type55))
                                  (i64.eqz
                                   (local.tee $1
                                    (i64.sub
                                     (local.get $1)
                                     (i64.const 1)
                                    )
                                   )
                                  )
                                  (then
                                   (ref.null none)
                                  )
                                  (else
                                   (if
                                    (i32.eqz
                                     (global.get $ready199)
                                    )
                                    (then
                                     (unreachable)
                                    )
                                   )
                                   (drop
                                    (ref.as_non_null
                                     (global.get $global199)
                                    )
                                   )
                                   (struct.new $type55
                                    (call $function70)
                                    (block (result (ref null $type55))
                                     (if
                                      (i32.eqz
                                       (global.get $ready207)
                                      )
                                      (then
                                       (unreachable)
                                      )
                                     )
                                     (drop
                                      (ref.as_non_null
                                       (global.get $global207)
                                      )
                                     )
                                     (if (result (ref null $type55))
                                      (i64.eqz
                                       (local.tee $1
                                        (i64.sub
                                         (local.get $1)
                                         (i64.const 1)
                                        )
                                       )
                                      )
                                      (then
                                       (ref.null none)
                                      )
                                      (else
                                       (if
                                        (i32.eqz
                                         (global.get $ready199)
                                        )
                                        (then
                                         (unreachable)
                                        )
                                       )
                                       (drop
                                        (ref.as_non_null
                                         (global.get $global199)
                                        )
                                       )
                                       (struct.new $type55
                                        (call $function70)
                                        (block (result (ref null $type55))
                                         (if
                                          (i32.eqz
                                           (global.get $ready207)
                                          )
                                          (then
                                           (unreachable)
                                          )
                                         )
                                         (drop
                                          (ref.as_non_null
                                           (global.get $global207)
                                          )
                                         )
                                         (if (result (ref null $type55))
                                          (i64.eqz
                                           (local.tee $1
                                            (i64.sub
                                             (local.get $1)
                                             (i64.const 1)
                                            )
                                           )
                                          )
                                          (then
                                           (ref.null none)
                                          )
                                          (else
                                           (if
                                            (i32.eqz
                                             (global.get $ready199)
                                            )
                                            (then
                                             (unreachable)
                                            )
                                           )
                                           (drop
                                            (ref.as_non_null
                                             (global.get $global199)
                                            )
                                           )
                                           (struct.new $type55
                                            (call $function70)
                                            (block (result (ref null $type55))
                                             (if
                                              (i32.eqz
                                               (global.get $ready207)
                                              )
                                              (then
                                               (unreachable)
                                              )
                                             )
                                             (drop
                                              (ref.as_non_null
                                               (global.get $global207)
                                              )
                                             )
                                             (if (result (ref null $type55))
                                              (i64.eqz
                                               (local.tee $1
                                                (i64.sub
                                                 (local.get $1)
                                                 (i64.const 1)
                                                )
                                               )
                                              )
                                              (then
                                               (ref.null none)
                                              )
                                              (else
                                               (if
                                                (i32.eqz
                                                 (global.get $ready199)
                                                )
                                                (then
                                                 (unreachable)
                                                )
                                               )
                                               (drop
                                                (ref.as_non_null
                                                 (global.get $global199)
                                                )
                                               )
                                               (struct.new $type55
                                                (call $function70)
                                                (block (result (ref null $type55))
                                                 (if
                                                  (i32.eqz
                                                   (global.get $ready207)
                                                  )
                                                  (then
                                                   (unreachable)
                                                  )
                                                 )
                                                 (drop
                                                  (ref.as_non_null
                                                   (global.get $global207)
                                                  )
                                                 )
                                                 (if (result (ref null $type55))
                                                  (i64.eqz
                                                   (local.tee $1
                                                    (i64.sub
                                                     (local.get $1)
                                                     (i64.const 1)
                                                    )
                                                   )
                                                  )
                                                  (then
                                                   (ref.null none)
                                                  )
                                                  (else
                                                   (if
                                                    (i32.eqz
                                                     (global.get $ready199)
                                                    )
                                                    (then
                                                     (unreachable)
                                                    )
                                                   )
                                                   (drop
                                                    (ref.as_non_null
                                                     (global.get $global199)
                                                    )
                                                   )
                                                   (struct.new $type55
                                                    (call $function70)
                                                    (block (result (ref null $type55))
                                                     (if
                                                      (i32.eqz
                                                       (global.get $ready207)
                                                      )
                                                      (then
                                                       (unreachable)
                                                      )
                                                     )
                                                     (drop
                                                      (ref.as_non_null
                                                       (global.get $global207)
                                                      )
                                                     )
                                                     (if (result (ref null $type55))
                                                      (i64.eqz
                                                       (local.tee $1
                                                        (i64.sub
                                                         (local.get $1)
                                                         (i64.const 1)
                                                        )
                                                       )
                                                      )
                                                      (then
                                                       (ref.null none)
                                                      )
                                                      (else
                                                       (if
                                                        (i32.eqz
                                                         (global.get $ready199)
                                                        )
                                                        (then
                                                         (unreachable)
                                                        )
                                                       )
                                                       (drop
                                                        (ref.as_non_null
                                                         (global.get $global199)
                                                        )
                                                       )
                                                       (struct.new $type55
                                                        (call $function70)
                                                        (block (result (ref null $type55))
                                                         (if
                                                          (i32.eqz
                                                           (global.get $ready207)
                                                          )
                                                          (then
                                                           (unreachable)
                                                          )
                                                         )
                                                         (drop
                                                          (ref.as_non_null
                                                           (global.get $global207)
                                                          )
                                                         )
                                                         (if (result (ref null $type55))
                                                          (i64.eqz
                                                           (local.tee $1
                                                            (i64.sub
                                                             (local.get $1)
                                                             (i64.const 1)
                                                            )
                                                           )
                                                          )
                                                          (then
                                                           (ref.null none)
                                                          )
                                                          (else
                                                           (if
                                                            (i32.eqz
                                                             (global.get $ready199)
                                                            )
                                                            (then
                                                             (unreachable)
                                                            )
                                                           )
                                                           (drop
                                                            (ref.as_non_null
                                                             (global.get $global199)
                                                            )
                                                           )
                                                           (struct.new $type55
                                                            (call $function70)
                                                            (block (result (ref null $type55))
                                                             (if
                                                              (i32.eqz
                                                               (global.get $ready207)
                                                              )
                                                              (then
                                                               (unreachable)
                                                              )
                                                             )
                                                             (drop
                                                              (ref.as_non_null
                                                               (global.get $global207)
                                                              )
                                                             )
                                                             (if (result (ref null $type55))
                                                              (i64.eqz
                                                               (local.tee $1
                                                                (i64.sub
                                                                 (local.get $1)
                                                                 (i64.const 1)
                                                                )
                                                               )
                                                              )
                                                              (then
                                                               (ref.null none)
                                                              )
                                                              (else
                                                               (if
                                                                (i32.eqz
                                                                 (global.get $ready199)
                                                                )
                                                                (then
                                                                 (unreachable)
                                                                )
                                                               )
                                                               (drop
                                                                (ref.as_non_null
                                                                 (global.get $global199)
                                                                )
                                                               )
                                                               (struct.new $type55
                                                                (call $function70)
                                                                (block (result (ref null $type55))
                                                                 (if
                                                                  (i32.eqz
                                                                   (global.get $ready207)
                                                                  )
                                                                  (then
                                                                   (unreachable)
                                                                  )
                                                                 )
                                                                 (drop
                                                                  (ref.as_non_null
                                                                   (global.get $global207)
                                                                  )
                                                                 )
                                                                 (call $function72
                                                                  (i64.sub
                                                                   (local.get $1)
                                                                   (i64.const 1)
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
     (block (result (ref null $type57))
      (if
       (i32.eqz
        (global.get $ready204)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global204)
       )
      )
      (call $function71
       (i64.sub
        (local.get $0)
        (i64.const 1)
       )
      )
     )
    )
   )
  )
 )
 (func $function72 (type $call63) (param $0 i64) (result (ref null $type55))
  (local $1 (ref $type27))
  (if (result (ref null $type55))
   (i64.eqz
    (local.get $0)
   )
   (then
    (ref.null none)
   )
   (else
    (if
     (i32.eqz
      (global.get $ready199)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global199)
     )
    )
    (struct.new $type55
     (call $function70)
     (block (result (ref null $type55))
      (if
       (i32.eqz
        (global.get $ready207)
       )
       (then
        (unreachable)
       )
      )
      (drop
       (ref.as_non_null
        (global.get $global207)
       )
      )
      (call $function72
       (i64.sub
        (local.get $0)
        (i64.const 1)
       )
      )
     )
    )
   )
  )
 )
 (func $function75 (type $3) (param $0 i64) (param $1 i32) (param $2 i32) (param $3 i64) (param $4 (ref $type36)) (result i64)
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
      (global.get $ready200)
     )
     (then
      (unreachable)
     )
    )
    (if
     (i32.eqz
      (global.get $ready212)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global212)
     )
    )
    (local.set $4
     (call $function51
      (call $foreign1
       (global.get $global200)
      )
      (block (result i64)
       (if
        (i32.eqz
         (global.get $ready201)
        )
        (then
         (unreachable)
        )
       )
       (if
        (i32.eqz
         (global.get $ready212)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global212)
        )
       )
       (local.set $scratch
        (call $foreign1
         (global.get $global201)
        )
       )
       (if
        (i32.eqz
         (global.get $ready141)
        )
        (then
         (unreachable)
        )
       )
       (drop
        (ref.as_non_null
         (global.get $global141)
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
    (return_call $function75
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
      (global.get $ready202)
     )
     (then
      (unreachable)
     )
    )
    (i64.extend_i32_u
     (i32.ne
      (if (result i32)
       (global.get $global202)
       (then
        (i32.const 0)
       )
       (else
        (if
         (i32.eqz
          (global.get $ready203)
         )
         (then
          (unreachable)
         )
        )
        (if
         (i32.eqz
          (global.get $ready129)
         )
         (then
          (unreachable)
         )
        )
        (drop
         (ref.as_non_null
          (global.get $global129)
         )
        )
        (call $function47
         (local.get $4)
         (global.get $global203)
        )
       )
      )
      (i32.const 0)
     )
    )
   )
  )
 )
 (func $export0 (param $0 i64) (result i64)
  (local $1 i64)
  (local $2 i64)
  (if
   (i32.ne
    (global.get $execution)
    (i32.const 2)
   )
   (then
    (unreachable)
   )
  )
  (if
   (i32.eqz
    (global.get $ready210)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global210)
   )
  )
  (if (result i64)
   (i64.le_s
    (local.get $0)
    (i64.const 0)
   )
   (then
    (if
     (i32.eqz
      (global.get $ready202)
     )
     (then
      (unreachable)
     )
    )
    (i64.extend_i32_u
     (i32.ne
      (global.get $global202)
      (i32.const 0)
     )
    )
   )
   (else
    (if
     (i32.eqz
      (global.get $ready200)
     )
     (then
      (unreachable)
     )
    )
    (if
     (i32.eqz
      (global.get $ready212)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global212)
     )
    )
    (local.set $1
     (call $foreign1
      (global.get $global200)
     )
    )
    (if
     (i32.eqz
      (global.get $ready201)
     )
     (then
      (unreachable)
     )
    )
    (if
     (i32.eqz
      (global.get $ready212)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global212)
     )
    )
    (local.set $2
     (call $foreign1
      (global.get $global201)
     )
    )
    (if
     (i32.eqz
      (global.get $ready141)
     )
     (then
      (unreachable)
     )
    )
    (drop
     (ref.as_non_null
      (global.get $global141)
     )
    )
    (return_call $function75
     (local.get $0)
     (i32.const 0)
     (i32.const 1)
     (i64.const 1)
     (call $function51
      (local.get $1)
      (local.get $2)
     )
    )
   )
  )
 )
 (func $main
  (local $0 i64)
  (local $1 (ref $type61))
  (local $scratch i64)
  (if
   (global.get $execution)
   (then
    (unreachable)
   )
  )
  (global.set $execution
   (i32.const 1)
  )
  (global.set $global109
   (struct.new_default $type28)
  )
  (global.set $ready109
   (i32.const 1)
  )
  (global.set $global148
   (struct.new_default $type30)
  )
  (global.set $ready148
   (i32.const 1)
  )
  (global.set $global155
   (struct.new_default $type40)
  )
  (global.set $ready155
   (i32.const 1)
  )
  (global.set $global120
   (struct.new_default $type41)
  )
  (global.set $ready120
   (i32.const 1)
  )
  (global.set $global132
   (struct.new_default $type42)
  )
  (global.set $ready132
   (i32.const 1)
  )
  (global.set $global125
   (struct.new_default $type43)
  )
  (global.set $ready125
   (i32.const 1)
  )
  (global.set $global137
   (struct.new_default $type44)
  )
  (global.set $ready137
   (i32.const 1)
  )
  (global.set $global127
   (struct.new_default $type45)
  )
  (global.set $ready127
   (i32.const 1)
  )
  (global.set $global139
   (struct.new_default $type46)
  )
  (global.set $ready139
   (i32.const 1)
  )
  (global.set $global158
   (struct.new_default $type47)
  )
  (global.set $ready158
   (i32.const 1)
  )
  (global.set $global187
   (struct.new_default $type48)
  )
  (global.set $ready187
   (i32.const 1)
  )
  (global.set $global170
   (struct.new_default $type49)
  )
  (global.set $ready170
   (i32.const 1)
  )
  (global.set $global110
   (struct.new_default $type50)
  )
  (global.set $ready110
   (i32.const 1)
  )
  (global.set $global194
   (struct.new_default $type51)
  )
  (global.set $ready194
   (i32.const 1)
  )
  (global.set $global178
   (struct.new_default $type52)
  )
  (global.set $ready178
   (i32.const 1)
  )
  (global.set $global114
   (struct.new_default $type53)
  )
  (global.set $ready114
   (i32.const 1)
  )
  (global.set $global117
   (struct.new_default $type54)
  )
  (global.set $ready117
   (i32.const 1)
  )
  (global.set $global129
   (struct.new_default $type56)
  )
  (global.set $ready129
   (i32.const 1)
  )
  (global.set $global212
   (struct.new_default $type58)
  )
  (global.set $ready212
   (i32.const 1)
  )
  (global.set $global164
   (struct.new_default $type59)
  )
  (global.set $ready164
   (i32.const 1)
  )
  (global.set $global141
   (struct.new_default $type60)
  )
  (global.set $ready141
   (i32.const 1)
  )
  (global.set $global196
   (struct.new_default $type61)
  )
  (global.set $ready196
   (i32.const 1)
  )
  (global.set $global197
   (struct.new_default $type5)
  )
  (global.set $ready197
   (i32.const 1)
  )
  (global.set $global199
   (struct.new_default $type62)
  )
  (global.set $ready199
   (i32.const 1)
  )
  (global.set $global207
   (struct.new_default $type63)
  )
  (global.set $ready207
   (i32.const 1)
  )
  (global.set $global204
   (struct.new_default $type64)
  )
  (global.set $ready204
   (i32.const 1)
  )
  (global.set $global200
   (call $foreign2
    (i32.const 0)
   )
  )
  (global.set $ready200
   (i32.const 1)
  )
  (global.set $global201
   (call $foreign2
    (i32.const 1)
   )
  )
  (global.set $ready201
   (i32.const 1)
  )
  (global.set $global202
   (i64.eq
    (call $foreign2
     (i32.const 2)
    )
    (i64.const 1)
   )
  )
  (global.set $ready202
   (i32.const 1)
  )
  (if
   (i32.eqz
    (global.get $ready197)
   )
   (then
    (unreachable)
   )
  )
  (drop
   (ref.as_non_null
    (global.get $global197)
   )
  )
  (if
   (i32.eqz
    (global.get $ready196)
   )
   (then
    (unreachable)
   )
  )
  (global.set $global203
   (call $function71
    (block (result i64)
     (local.set $scratch
      (call $foreign0
       (struct.get $type61 0
        (global.get $global196)
       )
      )
     )
     (if
      (i32.eqz
       (global.get $ready196)
      )
      (then
       (unreachable)
      )
     )
     (struct.set $type61 0
      (ref.as_non_null
       (global.get $global196)
      )
      (block (result i64)
       (if
        (i32.eqz
         (global.get $ready196)
        )
        (then
         (unreachable)
        )
       )
       (i64.add
        (struct.get $type61 0
         (global.get $global196)
        )
        (i64.const 1)
       )
      )
     )
     (if
      (i32.eqz
       (global.get $ready204)
      )
      (then
       (unreachable)
      )
     )
     (drop
      (ref.as_non_null
       (global.get $global204)
      )
     )
     (local.get $scratch)
    )
   )
  )
  (global.set $ready203
   (i32.const 1)
  )
  (global.set $global210
   (struct.new_default $type65)
  )
  (global.set $ready210
   (i32.const 1)
  )
  (global.set $execution
   (i32.const 2)
  )
 )
)

