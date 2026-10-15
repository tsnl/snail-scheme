;; Recursion groups define identity together; inherited fields retain their slots.
(define native-subtype-declarations
  '((rec
     (type $parent (sub (struct (field (mut i64)) (field (mut (ref null $parent))))))
     (type $left (sub final $parent
                      (struct (field (mut i64)) (field (mut (ref null $parent))) (field f32))))
     (type $right (sub final $parent
                       (struct (field (mut i64)) (field (mut (ref null $parent))) (field i32)))))
    (rec
     (type $same-parent (sub (struct (field (mut i64)) (field (mut (ref null $same-parent))))))
     (type $same-left (sub final $same-parent
                           (struct (field (mut i64)) (field (mut (ref null $same-parent))) (field f32))))
     (type $same-right (sub final $same-parent
                            (struct (field (mut i64)) (field (mut (ref null $same-parent))) (field i32)))))
    (func (export "left") (param $value i64) (result eqref) (local $self (ref null $left))
          (local.set $self (struct.new $left (local.get $value) (ref.null $parent) (f32.const 1.25)))
          (struct.set $parent 1 (local.get $self) (local.get $self))
          (local.get $self))
    (func (export "read-parent") (param $value eqref) (result i64)
          (struct.get $parent 0 (ref.cast (ref $parent) (local.get $value))))
    (func (export "read-right") (param $value eqref) (result i64)
          (struct.get $right 0 (ref.cast (ref $right) (local.get $value))))
    (func (export "same-left") (param $value eqref) (result i32)
          (ref.test (ref $same-left) (local.get $value)))
    (func (export "is-right") (param $value eqref) (result i32)
          (ref.test (ref $right) (local.get $value)))
    (func (export "cyclic") (param $value eqref) (result i32)
          (ref.eq (local.get $value) (struct.get $parent 1 (ref.cast (ref $parent) (local.get $value)))))))
