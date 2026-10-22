;; Inspect only Any's documented payload, so the integration test can ask
;; JavaScript whether two opaque, typed messages retain their GC identity.
(module
  (type $any (struct (field i32) (field anyref)))
  (func (export "payload") (param (ref $any)) (result anyref)
    (struct.get $any 1 (local.get 0))))
