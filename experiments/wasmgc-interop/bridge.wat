(module
  ;; ---- GC values and owned handle slots ----

  (type $pair (struct (field i31ref) (field i31ref)))
  (type $garbage (struct (field eqref) (field i32)))
  (table $roots 16 eqref)
  (global $live (mut i32) (i32.const 0))
  (global $garbage-root (mut eqref) (ref.null eq))

  ;; Slot zero is never allocated. Empty/out-of-range handles trap before
  ;; access. Slot reuse is unchecked: this proof has no generation counters.
  (func $get (param $handle i32) (result (ref $pair))
    (ref.cast (ref $pair) (table.get $roots (local.get $handle))))

  (func $hold (param $value (ref $pair)) (result i32)
    (local $slot i32)
    (local.set $slot (i32.const 1))
    (loop $find
      (if (ref.is_null (table.get $roots (local.get $slot)))
        (then
          (table.set $roots (local.get $slot) (local.get $value))
          (global.set $live (i32.add (global.get $live) (i32.const 1)))
          (return (local.get $slot))))
      (local.set $slot (i32.add (local.get $slot) (i32.const 1)))
      (br_if $find (i32.lt_u (local.get $slot) (i32.const 16))))
    unreachable)

  (func $release (export "release") (param $handle i32)
    (drop (call $get (local.get $handle)))
    (table.set $roots (local.get $handle) (ref.null eq))
    (global.set $live (i32.sub (global.get $live) (i32.const 1))))

  ;; ---- Direct imports for Rust ----

  (func (export "retain") (param $handle i32) (result i32)
    (call $hold (call $get (local.get $handle))))

  (func $make-pair (export "make_pair") (param $a i32) (param $b i32) (result i32)
    (call $hold (struct.new $pair (ref.i31 (local.get $a)) (ref.i31 (local.get $b)))))

  (func $first (export "first") (param $handle i32) (result i32)
    (i31.get_s (struct.get $pair 0 (call $get (local.get $handle)))))

  (func $second (export "second") (param $handle i32) (result i32)
    (i31.get_s (struct.get $pair 1 (call $get (local.get $handle)))))

  ;; ---- Driver adapters ----

  (func (export "live_roots") (result i32) (global.get $live))

  (func (export "take_sum") (param $handle i32) (result i32)
    (local $pair (ref $pair))
    (local.set $pair (call $get (local.get $handle)))
    (call $release (local.get $handle))
    (i32.add
      (i31.get_s (struct.get $pair 0 (local.get $pair)))
      (i31.get_s (struct.get $pair 1 (local.get $pair)))))

  ;; Allocate garbage before asking V8 for a full collection in the JS driver.
  (func (export "churn") (param $count i32)
    (loop $again
      (global.set $garbage-root
        (struct.new $garbage (global.get $garbage-root) (local.get $count)))
      (local.set $count (i32.sub (local.get $count) (i32.const 1)))
      (br_if $again (local.get $count))))

  (func (export "discard_garbage")
    (global.set $garbage-root (ref.null eq)))
)
