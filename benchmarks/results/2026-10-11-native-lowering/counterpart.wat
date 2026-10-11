(module
  (type $words (array (mut i64)))
  (func (export "construct") (param i64 i64 i64) (result (ref $words))
    (array.new_fixed $words 3 (local.get 0) (local.get 1) (local.get 2)))
  (func (export "roundtrip") (param i64 i64 i64) (result i64)
    (array.get $words
      (array.new_fixed $words 3 (local.get 0) (local.get 1) (local.get 2))
      (i32.const 1))))
