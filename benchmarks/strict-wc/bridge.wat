;; ---- Three native counters and the ordinary Scheme result ----

;; These diagnostic globals hold scalars, never GC addresses. Invocations are
;; synchronous and do not overlap; each successful EOF submits all three anew.
(global $probe:lines (mut i64) (i64.const 0))
(global $probe:words (mut i64) (i64.const 0))
(global $probe:characters (mut i64) (i64.const 0))
(func $probe:counts (export "probe:counts")
  (param $lines i64) (param $words i64) (param $characters i64)
  (global.set $probe:lines (local.get $lines))
  (global.set $probe:words (local.get $words))
  (global.set $probe:characters (local.get $characters)))
(func $probe:result (result eqref)
  ;; The Wasm engine traces GC references on the operand stack during these
  ;; allocations. No Rust callback borrows an unrooted intermediate value.
  (call $cons (call $pack_integer (global.get $probe:lines))
    (call $cons (call $pack_integer (global.get $probe:words))
      (call $cons (call $pack_integer (global.get $probe:characters))
        (global.get $nil)))))

;; ---- Explicit legacy owner and functional probes ----

(func $prototype_port_id (param $value eqref) (result i32)
  (local $port (ref $extension))
  (local.set $port (ref.cast (ref $extension) (local.get $value)))
  (if (i32.ne (struct.get $extension 0 (local.get $port)) (i32.const 1))
    (then (call $fail (i32.const 8))))
  (struct.get $extension 1 (local.get $port)))
(func (export "test/wcport") (param $input-root i32) (result i32)
  (call $abi_root
    (call $function171 (ref.null eq) (call $abi_get (local.get $input-root))
      (ref.null $result_context))))
(func (export "test/count-result")
  (param $lines i64) (param $words i64) (param $characters i64) (result i32)
  (call $probe:counts (local.get $lines) (local.get $words) (local.get $characters))
  (call $abi_root (call $probe:result)))
