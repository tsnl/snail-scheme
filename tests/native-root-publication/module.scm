;; Operand-only roots cross allocations, imported collection, control joins and
;; a tail transfer. The array keeps two aliases to a moving initializer.
(module
 (type $box (struct (field i64)))
 (type $refs (array (ref null $box)))
 (import "probe" "collect" (func $collect (result i32)))
 (import "probe" "collect-two" (func $collect-two))
 (func $sum (param $a (ref $box)) (param $b (ref $box)) (param $c (ref $box)) (param i32) (result i64)
       (drop (call $collect))
       (i64.add (struct.get $box 0 (local.get $a))
                (i64.add (struct.get $box 0 (local.get $b)) (struct.get $box 0 (local.get $c)))))
 (func (export "run") (param $condition i32) (result i64) (local $n i32)
       (return_call $sum
                    (struct.new $box (i64.const 11))
                    (struct.new $box (i64.const 22))
                    (block (result (ref $box)) (call $collect-two) (struct.new $box (i64.const 33)))
                    (block (result i32)
                           (drop (call $collect))
                           (local.set $n (i32.const 3))
                           (loop $again
                                 (drop (call $collect))
                                 (local.set $n (i32.sub (local.get $n) (i32.const 1)))
                                 (br_if $again (local.get $n)))
                           (if (local.get $condition)
                               (then (drop (struct.new $box (i64.const 44))) (drop (call $collect)))
                               (else (drop (struct.new $box (i64.const 55))) (drop (call $collect))))
                           (i32.const 0))))
 (func (export "arrays") (result i64) (local $array (ref null $refs))
       (local.set $array (array.new $refs (struct.new $box (i64.const 21)) (i32.const 2)))
       (i64.add
        (struct.get $box 0 (array.get $refs (local.get $array) (i32.const 0)))
        (struct.get $box 0
                    (array.get $refs
                               (block (result (ref $refs))
                                      (ref.as_non_null (local.get $array))
                                      (local.set $array (ref.null $refs))
                                      (drop (struct.new $box (i64.const 1)))
                                      (drop (struct.new $box (i64.const 2))))
                               (i32.const 1))))))
