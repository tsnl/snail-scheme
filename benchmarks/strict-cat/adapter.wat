;; Replaces the frozen catport's resolved function. Program controls, file
;; opening/closing and timing remain in the original benchmark harness.
(func $function171 (param $env eqref) (param $a0 eqref) (param $a1 eqref)
  (param $checks (ref null $result_context)) (result eqref)
  (local $input-root i32) (local $output-root i32)
  (local.set $input-root (call $abi_root (local.get $a0)))
  (local.set $output-root (call $abi_root (local.get $a1)))
  (global.set $probe:output (local.get $a1))
  (call $strict:copy-code (call $prototype_port_id (local.get $a0)))
  (global.set $probe:output (ref.null eq))
  (call $abi_release (local.get $output-root))
  (call $abi_release (local.get $input-root))
  (global.get $unspecified))
