(module
  (type $object (struct (field i32)))
  (global $held (mut eqref) (ref.null eq))
  (func (export "make") (result eqref) (struct.new $object (i32.const 42)))
  (func (export "hold") (param eqref) (global.set $held (local.get 0)))
  (func (export "release") (global.set $held (ref.null eq))))
