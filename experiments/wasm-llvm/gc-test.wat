(module
  (type $pair (struct (field eqref) (field eqref)))
  (import "env" "collect" (func $collect))
  (import "env" "observe" (func $observe (param eqref)))
  (global $root (mut eqref) (ref.null eq))

  ;; ---- Heap construction ----

  (func $pair (param $a i32) (param $b i32) (result eqref)
    (struct.new $pair (ref.i31 (local.get $a)) (ref.i31 (local.get $b))))

  (func $tree (param $depth i32) (result eqref)
    (if (result eqref) (i32.eqz (local.get $depth))
      (then (ref.i31 (i32.const 1)))
      (else (struct.new $pair
        (call $tree (i32.sub (local.get $depth) (i32.const 1)))
        (call $tree (i32.sub (local.get $depth) (i32.const 1)))))))

  (func $garbage
    (call $observe (call $pair (i32.const 999) (i32.const 1000))))

  ;; ---- Read initialized fields after collection ----

  (func $sum_pair (param $value eqref) (result i32)
    (i32.add
      (i31.get_s (ref.cast (ref i31)
        (struct.get $pair 0 (ref.cast (ref $pair) (local.get $value)))))
      (i31.get_s (ref.cast (ref i31)
        (struct.get $pair 1 (ref.cast (ref $pair) (local.get $value)))))))

  (func $sum_tree (param $value eqref) (result i32)
    (if (result i32) (ref.test (ref i31) (local.get $value))
      (then (i31.get_s (ref.cast (ref i31) (local.get $value))))
      (else (i32.add
        (call $sum_tree (struct.get $pair 0 (ref.cast (ref $pair) (local.get $value))))
        (call $sum_tree (struct.get $pair 1 (ref.cast (ref $pair) (local.get $value))))))))

  ;; ---- More live roots than native callee-saved registers ----

  (func $registers_and_spills (result i32)
    (local $a eqref) (local $b eqref) (local $c eqref) (local $d eqref)
    (local $e eqref) (local $f eqref) (local $g eqref) (local $h eqref)
    (local.set $a (call $pair (i32.const 1) (i32.const 101)))
    (local.set $b (call $pair (i32.const 2) (i32.const 102)))
    (local.set $c (call $pair (i32.const 3) (i32.const 103)))
    (local.set $d (call $pair (i32.const 4) (i32.const 104)))
    (local.set $e (call $pair (i32.const 5) (i32.const 105)))
    (local.set $f (call $pair (i32.const 6) (i32.const 106)))
    (local.set $g (call $pair (i32.const 7) (i32.const 107)))
    (local.set $h (call $pair (i32.const 8) (i32.const 108)))
    (call $observe (local.get $a)) (call $observe (local.get $b))
    (call $observe (local.get $c)) (call $observe (local.get $d))
    (call $observe (local.get $e)) (call $observe (local.get $f))
    (call $observe (local.get $g)) (call $observe (local.get $h))
    (call $collect)
    (call $observe (local.get $a)) (call $observe (local.get $b))
    (call $observe (local.get $c)) (call $observe (local.get $d))
    (call $observe (local.get $e)) (call $observe (local.get $f))
    (call $observe (local.get $g)) (call $observe (local.get $h))
    (i32.add
      (i32.add
        (i32.add (call $sum_pair (local.get $a)) (call $sum_pair (local.get $b)))
        (i32.add (call $sum_pair (local.get $c)) (call $sum_pair (local.get $d))))
      (i32.add
        (i32.add (call $sum_pair (local.get $e)) (call $sum_pair (local.get $f)))
        (i32.add (call $sum_pair (local.get $g)) (call $sum_pair (local.get $h))))))

  ;; ---- Global, caller-frame, register, and spill roots ----

  (func (export "gc_probe") (result i32)
    (local $tree eqref) (local $sum i32)
    (global.set $root (call $pair (i32.const 41) (i32.const 42)))
    (local.set $tree (call $tree (i32.const 7)))
    (call $observe (local.get $tree))
    (call $observe (global.get $root))
    (call $garbage)
    (local.set $sum (call $registers_and_spills))
    (call $collect)
    (call $observe (global.get $root))
    (call $observe (local.get $tree))
    (i32.add (local.get $sum)
      (i32.add (call $sum_pair (global.get $root)) (call $sum_tree (local.get $tree)))))
)
