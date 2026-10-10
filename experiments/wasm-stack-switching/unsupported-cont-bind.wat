(module
  (type $worker (func (param i64) (result i64)))
  (type $continuation (cont $worker))
  (func $worker (type $worker) (param $x i64) (result i64) (local.get $x))
  (elem declare func $worker)
  (func $bind (export "bind") (result (ref $continuation))
    (cont.bind $continuation $continuation
      (cont.new $continuation (ref.func $worker)))))
