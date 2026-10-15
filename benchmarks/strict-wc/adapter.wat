;; Replaces only the frozen wcport function. The original Scheme harness still
;; owns file opening/closing, fifty repetitions, timing, and its list predicate.
(func $function171 (param $env eqref) (param $a0 eqref)
  (param $checks (ref null $result_context)) (result eqref)
  (local $input-root i32) (local $result eqref)
  ;; A numeric resource ID does not keep its GC wrapper alive. Retain that owner
  ;; through every native read and the final Scheme result allocation.
  (local.set $input-root (call $abi_root (local.get $a0)))
  (call $strict:count-code (call $prototype_port_id (local.get $a0)))
  (local.set $result (call $probe:result))
  (call $abi_release (local.get $input-root))
  (local.get $result))
