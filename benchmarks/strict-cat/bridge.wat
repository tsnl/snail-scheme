;; Only the adapter stores this wrapper. It retains its owned root until the
;; entire copy finishes, then clears this additional GC reference before release.
;; No Rust/native service receives a numeric address for a GC object.
(global $probe:output (mut eqref) (ref.null eq))
(func $probe:output-id (export "probe:output-id") (result i32)
  (call $prototype_port_id (global.get $probe:output)))
